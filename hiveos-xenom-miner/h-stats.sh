#!/usr/bin/env bash
# This script provides miner statistics in JSON format
# It's included in the agent script, so agent variables are available

# Get stats from log file
LOG_FILE="${CUSTOM_LOG_BASENAME}.log"

# Initialize default values
local total_hs=0
local blocks_found=0
local blocks_accepted=0
local blocks_rejected=0
local uptime=0
local current_height=0
local num_gpus=0

# Arrays for per-GPU stats
declare -a gpu_hs=()
declare -a gpu_temp=()
declare -a gpu_fan=()
declare -a gpu_bus=()

# Parse the log file for stats
if [[ -f "$LOG_FILE" ]]; then
    # Get uptime - use miner start time or first log entry
    local start_line=$(grep "Starting Xenom GPU Miner\|Starting continuous mining loop" "$LOG_FILE" | head -n 1)
    if [[ -n "$start_line" ]]; then
        # Try to get process start time from ps
        local miner_pid=$(pgrep -f "xenom-miner-rust" | head -n 1)
        if [[ -n "$miner_pid" ]]; then
            uptime=$(ps -o etimes= -p "$miner_pid" 2>/dev/null | tr -d ' ' || echo 0)
        fi
    fi
    
    # If uptime is still 0, estimate from log file modification time
    if [[ $uptime -eq 0 ]]; then
        local log_age=$(($(date +%s) - $(stat -f %m "$LOG_FILE" 2>/dev/null || echo $(date +%s))))
        uptime=$log_age
    fi
    
    # Count blocks found (solutions)
    blocks_found=$(grep -c "SOLUTION FOUND" "$LOG_FILE" 2>/dev/null || echo 0)
    blocks_accepted=$(grep -c "✅ Solution submitted successfully" "$LOG_FILE" 2>/dev/null || echo 0)
    blocks_rejected=$(grep -c "❌ Failed to submit solution\|Solution rejected" "$LOG_FILE" 2>/dev/null || echo 0)
    
    # Get current mining height
    current_height=$(grep "Mining block" "$LOG_FILE" | tail -n 1 | grep -oE 'block [0-9]+' | grep -oE '[0-9]+' || echo 0)
    
    # Detect number of GPUs from log
    num_gpus=$(grep "GPUs:" "$LOG_FILE" | tail -n 1 | grep -oE '[0-9]+ device' | grep -oE '[0-9]+' || echo 1)
    
    # Calculate hashrate from batch progress logs
    # Look for "Batch X/Y, Z hashes" entries to estimate hashrate
    local last_batch_line=$(grep "Batch.*hashes" "$LOG_FILE" | tail -n 1)
    if [[ -n "$last_batch_line" ]]; then
        local total_hashes=$(echo "$last_batch_line" | grep -oE '[0-9]+ hashes' | grep -oE '[0-9]+')
        if [[ -n "$total_hashes" && $uptime -gt 0 ]]; then
            total_hs=$(echo "scale=0; $total_hashes / $uptime" | bc 2>/dev/null || echo 0)
        fi
    fi
    
    # If no batch info, estimate from batches parameter and uptime
    if [[ $total_hs -eq 0 && $uptime -gt 10 ]]; then
        # Default: 40000 batches * population (assume 1M per batch)
        local est_hashes=$((uptime * 1000000))
        total_hs=$(echo "scale=0; $est_hashes / $uptime" | bc 2>/dev/null || echo 1000000)
    fi
    
    # Get per-GPU hashrate (divide total by number of GPUs)
    if [[ $num_gpus -gt 0 ]]; then
        local hs_per_gpu=$(echo "scale=0; $total_hs / $num_gpus" | bc 2>/dev/null || echo 0)
        for ((i=0; i<$num_gpus; i++)); do
            gpu_hs+=("$hs_per_gpu")
        done
    else
        gpu_hs+=("$total_hs")
        num_gpus=1
    fi
    
    # Get GPU temperatures and fan speeds from nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        local gpu_stats=$(nvidia-smi --query-gpu=index,temperature.gpu,fan.speed,pci.bus_id --format=csv,noheader,nounits 2>/dev/null)
        if [[ -n "$gpu_stats" ]]; then
            while IFS=', ' read -r idx temp fan bus; do
                gpu_temp+=("$temp")
                gpu_fan+=("${fan:-0}")
                # Extract bus number (e.g., "00000000:01:00.0" -> "01")
                local bus_num=$(echo "$bus" | cut -d':' -f2)
                gpu_bus+=("$bus_num")
            done <<< "$gpu_stats"
        fi
    fi
    
    # Fill missing GPU stats with zeros if nvidia-smi failed
    while [[ ${#gpu_temp[@]} -lt $num_gpus ]]; do
        gpu_temp+=(0)
        gpu_fan+=(0)
        gpu_bus+=(0)
    done
fi

# Build hashrate array (convert to strings for jq)
local hs_array=""
for hs in "${gpu_hs[@]}"; do
    hs_array="${hs_array}\"${hs}\","
done
hs_array="[${hs_array%,}]"

# Build temp array
local temp_array=""
for temp in "${gpu_temp[@]}"; do
    temp_array="${temp_array}\"${temp}\","
done
temp_array="[${temp_array%,}]"

# Build fan array
local fan_array=""
for fan in "${gpu_fan[@]}"; do
    fan_array="${fan_array}\"${fan}\","
done
fan_array="[${fan_array%,}]"

# Build bus array
local bus_array=""
for bus in "${gpu_bus[@]}"; do
    bus_array="${bus_array}\"${bus}\","
done
bus_array="[${bus_array%,}]"

# Build stats JSON
# HiveOS expects: hs (array), temp (array), fan (array), ar (accepted/rejected as shares)
stats=$(jq -nc \
    --argjson hs "$hs_array" \
    --argjson temp "$temp_array" \
    --argjson fan "$fan_array" \
    --argjson bus "$bus_array" \
    --arg blocks_accepted "$blocks_accepted" \
    --arg blocks_rejected "$blocks_rejected" \
    --arg uptime "$uptime" \
    --arg height "$current_height" \
    '{
        hs: $hs,
        hs_units: "hs",
        temp: $temp,
        fan: $fan,
        uptime: ($uptime | tonumber),
        ver: "1.0.0",
        ar: [($blocks_accepted | tonumber), ($blocks_rejected | tonumber)],
        algo: "xenom-pow",
        bus_numbers: $bus
    }')

# Set required variables for HiveOS
# Total hashrate in khs
local total_khs=$(echo "scale=3; $total_hs / 1000" | bc 2>/dev/null || echo 0)
khs=$total_khs

# Debug output (will appear in agent logs)
[[ -n "$CUSTOM_LOG_BASENAME" ]] && echo "$(date): Xenom stats: GPUs=$num_gpus, khs=$khs, shares=$blocks_accepted/$blocks_rejected, uptime=${uptime}s" >> "${CUSTOM_LOG_BASENAME}-stats.log"
