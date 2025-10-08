#!/usr/bin/env bash
# This script provides miner statistics in JSON format
# It's included in the agent script, so agent variables are available

# Setup debug logging
DEBUG_LOG="/tmp/xenom-stats-debug.log"
STATS_LOG="${CUSTOM_LOG_BASENAME}-stats.log"

# Fallback if CUSTOM_LOG_BASENAME is not set
if [[ -z "$CUSTOM_LOG_BASENAME" || "$CUSTOM_LOG_BASENAME" == "" ]]; then
    CUSTOM_LOG_BASENAME="/var/log/miner/custom/hiveos-xenom-miner/xenom"
    STATS_LOG="/var/log/miner/custom/hiveos-xenom-miner/xenom-stats.log"
fi

# Get stats from log file
LOG_FILE="${CUSTOM_LOG_BASENAME}.log"
[[ -z "$LOG_FILE" || "$LOG_FILE" == ".log" ]] && LOG_FILE="/var/log/miner/custom/hiveos-xenom-miner/xenom.log"

# Log script execution
echo "=== h-stats.sh executed at $(date) ===" >> "$DEBUG_LOG" 2>&1
echo "CUSTOM_LOG_BASENAME=$CUSTOM_LOG_BASENAME" >> "$DEBUG_LOG" 2>&1
echo "LOG_FILE=$LOG_FILE" >> "$DEBUG_LOG" 2>&1
echo "STATS_LOG=$STATS_LOG" >> "$DEBUG_LOG" 2>&1

# Initialize default values
total_hs=0
blocks_found=0
blocks_accepted=0
blocks_rejected=0
uptime=0
current_height=0
num_gpus=0

# Arrays for per-GPU stats
declare -a gpu_hs=()
declare -a gpu_temp=()
declare -a gpu_fan=()
declare -a gpu_bus=()

# Parse the log file for stats
if [[ -f "$LOG_FILE" ]]; then
    # Get uptime - use miner start time or first log entry
    start_line=$(grep "Starting Xenom GPU Miner\|Starting continuous mining loop" "$LOG_FILE" | head -n 1)
    if [[ -n "$start_line" ]]; then
        # Try to get process start time from ps
        miner_pid=$(pgrep -f "xenom-miner-rust" | head -n 1)
        if [[ -n "$miner_pid" ]]; then
            uptime=$(ps -o etimes= -p "$miner_pid" 2>/dev/null | tr -d ' ' || echo 0)
        fi
    fi
    
    # If uptime is still 0, estimate from log file modification time
    if [[ $uptime -eq 0 ]]; then
        log_age=$(($(date +%s) - $(stat -f %m "$LOG_FILE" 2>/dev/null || echo $(date +%s))))
        uptime=$log_age
    fi
    
    # Count blocks found (solutions)
    blocks_found=$(grep -c "SOLUTION FOUND" "$LOG_FILE" 2>/dev/null | tr -d '\n' || echo 0)
    blocks_accepted=$(grep -c "BLOCK ACCEPTED" "$LOG_FILE" 2>/dev/null | tr -d '\n' || echo 0)
    blocks_rejected=$(grep -c "Solution rejected" "$LOG_FILE" 2>/dev/null | tr -d '\n' || echo 0)
    
    # Ensure they're valid numbers
    [[ ! "$blocks_found" =~ ^[0-9]+$ ]] && blocks_found=0
    [[ ! "$blocks_accepted" =~ ^[0-9]+$ ]] && blocks_accepted=0
    [[ ! "$blocks_rejected" =~ ^[0-9]+$ ]] && blocks_rejected=0
    [[ ! "$uptime" =~ ^[0-9]+$ ]] && uptime=0
    
    # Get current mining height
    current_height=$(grep "Mining block" "$LOG_FILE" | tail -n 1 | grep -oE 'block [0-9]+' | grep -oE '[0-9]+' || echo 0)
    [[ ! "$current_height" =~ ^[0-9]+$ ]] && current_height=0
    
    # Detect number of GPUs from log
    num_gpus=$(grep "GPUs:" "$LOG_FILE" | tail -n 1 | grep -oE '[0-9]+ device' | grep -oE '[0-9]+' || echo 1)
    echo "Detected $num_gpus GPUs from log" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
    
    # Parse hashrate from miner output
    # Look for "Total hashrate: X.XX MH/s" or "Per-GPU: X.XX MH/s"
    total_hashrate_line=$(grep "Total hashrate:" "$LOG_FILE" | tail -n 1)
    if [[ -n "$total_hashrate_line" ]]; then
        # Extract MH/s value and convert to H/s
        mhs=$(echo "$total_hashrate_line" | grep -oE '[0-9]+\.[0-9]+ MH/s' | grep -oE '[0-9]+\.[0-9]+')
        if [[ -n "$mhs" ]]; then
            total_hs=$(echo "scale=0; $mhs * 1000000 / 1" | bc 2>/dev/null || echo 0)
        fi
    fi
    
    # If no total hashrate, try per-GPU hashrate
    if [[ $total_hs -eq 0 ]]; then
        per_gpu_line=$(grep "Per-GPU:" "$LOG_FILE" | tail -n 1)
        if [[ -n "$per_gpu_line" ]]; then
            mhs=$(echo "$per_gpu_line" | grep -oE '[0-9]+\.[0-9]+ MH/s' | grep -oE '[0-9]+\.[0-9]+')
            if [[ -n "$mhs" ]]; then
                per_gpu_hs=$(echo "scale=0; $mhs * 1000000 / 1" | bc 2>/dev/null || echo 0)
                total_hs=$((per_gpu_hs * num_gpus))
            fi
        fi
    fi
    
    # Fallback: estimate from batch progress logs
    if [[ $total_hs -eq 0 ]]; then
        last_batch_line=$(grep "Batch.*hashes" "$LOG_FILE" | tail -n 1)
        if [[ -n "$last_batch_line" ]]; then
            total_hashes=$(echo "$last_batch_line" | grep -oE '[0-9]+ hashes' | grep -oE '[0-9]+')
            if [[ -n "$total_hashes" && $uptime -gt 0 ]]; then
                total_hs=$(echo "scale=0; $total_hashes / $uptime" | bc 2>/dev/null || echo 0)
            fi
        fi
    fi
    
    # Get per-GPU hashrate (divide total by number of GPUs)
    # Convert to kH/s for HiveOS compatibility
    if [[ $num_gpus -gt 0 ]]; then
        hs_per_gpu=$(echo "scale=2; $total_hs / $num_gpus / 1000" | bc 2>/dev/null || echo 0)
        for ((i=0; i<$num_gpus; i++)); do
            gpu_hs+=("$hs_per_gpu")
        done
    else
        gpu_hs+=("$(echo "scale=2; $total_hs / 1000" | bc 2>/dev/null || echo 0)")
        num_gpus=1
    fi
    
    # Get GPU temperatures and fan speeds from nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        # Simple approach: query each GPU individually
        for ((i=0; i<$num_gpus; i++)); do
            temp=$(nvidia-smi -i $i --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | xargs)
            fan=$(nvidia-smi -i $i --query-gpu=fan.speed --format=csv,noheader,nounits 2>/dev/null | xargs)
            bus=$(nvidia-smi -i $i --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | xargs)
            
            # Debug each query
            echo "GPU $i: temp='$temp' fan='$fan' bus='$bus'" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
            
            # Validate and add to arrays
            if [[ "$temp" =~ ^[0-9]+$ ]]; then
                gpu_temp+=("$temp")
            else
                gpu_temp+=(0)
                echo "GPU $i: Invalid temp, using 0" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
            fi
            
            if [[ "$fan" =~ ^[0-9]+$ ]]; then
                gpu_fan+=("$fan")
            else
                gpu_fan+=(0)
                echo "GPU $i: Invalid fan, using 0" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
            fi
            
            # Extract bus number
            if [[ -n "$bus" ]]; then
                bus_num=$(echo "$bus" | cut -d':' -f2)
                gpu_bus+=("$bus_num")
            else
                gpu_bus+=("$i")
            fi
        done
        
        # Debug: log what we got
        echo "nvidia-smi results: temps=[${gpu_temp[*]}] fans=[${gpu_fan[*]}] count=${#gpu_temp[@]}" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
    else
        echo "nvidia-smi not found!" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
    fi
    
    # Fill missing GPU stats with zeros if nvidia-smi failed
    while [[ ${#gpu_temp[@]} -lt $num_gpus ]]; do
        gpu_temp+=(0)
        gpu_fan+=(0)
        gpu_bus+=(0)
    done
    
    # Debug: log parsed GPU stats
    echo "Parsed GPU stats: temps=[${gpu_temp[*]}] fans=[${gpu_fan[*]}] bus=[${gpu_bus[*]}]" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
else
    # Log file not found - provide minimal stats
    echo "Warning: Log file not found at $LOG_FILE" >&2
    num_gpus=1
    gpu_hs+=(0)
    gpu_temp+=(0)
    gpu_fan+=(0)
    gpu_bus+=(0)
fi

# Ensure arrays have at least one element
[[ ${#gpu_hs[@]} -eq 0 ]] && gpu_hs=(0)
[[ ${#gpu_temp[@]} -eq 0 ]] && gpu_temp=(0)
[[ ${#gpu_fan[@]} -eq 0 ]] && gpu_fan=(0)
[[ ${#gpu_bus[@]} -eq 0 ]] && gpu_bus=(0)

# Build stats JSON using HiveOS standard method
# Convert arrays to jq format - need to handle numeric values properly
hs_array=$(printf '%s\n' "${gpu_hs[@]}" | jq -cs 'map(tonumber)')
temp_array=$(printf '%s\n' "${gpu_temp[@]}" | jq -cs 'map(tonumber)')
fan_array=$(printf '%s\n' "${gpu_fan[@]}" | jq -cs 'map(tonumber)')
# Bus IDs are strings, wrap in quotes for jq
bus_array=$(printf '"%s"\n' "${gpu_bus[@]}" | jq -cs '.')

echo "Building JSON with: hs=$hs_array temp=$temp_array fan=$fan_array bus=$bus_array" | tee -a "$DEBUG_LOG" 2>/dev/null

stats=$(jq -nc \
    --arg hs_units "khs" \
    --argjson hs "$hs_array" \
    --argjson temp "$temp_array" \
    --argjson fan "$fan_array" \
    --arg uptime "$uptime" \
    --arg ver "1.0.0" \
    --arg ac "$blocks_accepted" \
    --arg rj "$blocks_rejected" \
    --arg algo "xenom-pow" \
    --argjson bus_numbers "$bus_array" \
    '{$hs, $hs_units, $temp, $fan, $uptime, $ver, ar: [$ac, $rj], $algo, $bus_numbers}' 2>&1)

jq_exit=$?
echo "jq exit code: $jq_exit" | tee -a "$DEBUG_LOG" 2>/dev/null

if [[ $jq_exit -ne 0 ]]; then
    echo "jq error: $stats" | tee -a "$DEBUG_LOG" 2>/dev/null
fi

# Set required variables for HiveOS
# Total hashrate in khs
total_khs=$(echo "scale=3; $total_hs / 1000" | bc 2>/dev/null || echo 0)
khs=$total_khs

# Debug output (will appear in agent logs)
echo "$(date): Xenom stats: GPUs=$num_gpus, khs=$khs, shares=$blocks_accepted/$blocks_rejected, uptime=${uptime}s" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
echo "Arrays: hs=$hs_array temp=$temp_array fan=$fan_array" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null

# Output for debugging
echo "stats=$stats" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null
echo "khs=$khs" | tee -a "$DEBUG_LOG" "$STATS_LOG" 2>/dev/null

# Final summary
echo "=== Stats script completed ===" >> "$DEBUG_LOG" 2>&1
