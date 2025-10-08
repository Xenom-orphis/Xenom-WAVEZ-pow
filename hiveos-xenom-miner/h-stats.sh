#!/usr/bin/env bash
# This script provides miner statistics in JSON format
# It's included in the agent script, so agent variables are available

# Get stats from log file
LOG_FILE="${CUSTOM_LOG_BASENAME}.log"

# Fallback if CUSTOM_LOG_BASENAME is not set
[[ -z "$LOG_FILE" || "$LOG_FILE" == ".log" ]] && LOG_FILE="/var/log/miner/custom/hiveos-xenom-miner/xenom.log"

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
    blocks_found=$(grep -c "SOLUTION FOUND" "$LOG_FILE" 2>/dev/null || echo 0)
    blocks_accepted=$(grep -c "BLOCK ACCEPTED" "$LOG_FILE" 2>/dev/null || echo 0)
    blocks_rejected=$(grep -c "Solution rejected" "$LOG_FILE" 2>/dev/null || echo 0)
    
    # Get current mining height
    current_height=$(grep "Mining block" "$LOG_FILE" | tail -n 1 | grep -oE 'block [0-9]+' | grep -oE '[0-9]+' || echo 0)
    
    # Detect number of GPUs from log
    num_gpus=$(grep "GPUs:" "$LOG_FILE" | tail -n 1 | grep -oE '[0-9]+ device' | grep -oE '[0-9]+' || echo 1)
    echo "Detected $num_gpus GPUs from log" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
    
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
    if [[ $num_gpus -gt 0 ]]; then
        hs_per_gpu=$(echo "scale=0; $total_hs / $num_gpus" | bc 2>/dev/null || echo 0)
        for ((i=0; i<$num_gpus; i++)); do
            gpu_hs+=("$hs_per_gpu")
        done
    else
        gpu_hs+=("$total_hs")
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
            echo "GPU $i: temp='$temp' fan='$fan' bus='$bus'" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
            
            # Validate and add to arrays
            if [[ "$temp" =~ ^[0-9]+$ ]]; then
                gpu_temp+=("$temp")
            else
                gpu_temp+=(0)
                echo "GPU $i: Invalid temp, using 0" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
            fi
            
            if [[ "$fan" =~ ^[0-9]+$ ]]; then
                gpu_fan+=("$fan")
            else
                gpu_fan+=(0)
                echo "GPU $i: Invalid fan, using 0" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
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
        echo "nvidia-smi results: temps=[${gpu_temp[*]}] fans=[${gpu_fan[*]}] count=${#gpu_temp[@]}" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
    else
        echo "nvidia-smi not found!" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
    fi
    
    # Fill missing GPU stats with zeros if nvidia-smi failed
    while [[ ${#gpu_temp[@]} -lt $num_gpus ]]; do
        gpu_temp+=(0)
        gpu_fan+=(0)
        gpu_bus+=(0)
    done
    
    # Debug: log parsed GPU stats
    echo "Parsed GPU stats: temps=[${gpu_temp[*]}] fans=[${gpu_fan[*]}] bus=[${gpu_bus[*]}]" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
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

# Build hashrate array (numeric values, no quotes)
hs_array=""
for hs in "${gpu_hs[@]}"; do
    hs_array="${hs_array}${hs},"
done
hs_array="[${hs_array%,}]"

# Build temp array (numeric values, no quotes)
temp_array=""
for temp in "${gpu_temp[@]}"; do
    temp_array="${temp_array}${temp},"
done
temp_array="[${temp_array%,}]"

# Build fan array (numeric values, no quotes)
fan_array=""
for fan in "${gpu_fan[@]}"; do
    fan_array="${fan_array}${fan},"
done
fan_array="[${fan_array%,}]"

# Build bus array (strings with quotes)
bus_array=""
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
total_khs=$(echo "scale=3; $total_hs / 1000" | bc 2>/dev/null || echo 0)
khs=$total_khs

# Debug output (will appear in agent logs)
echo "$(date): Xenom stats: GPUs=$num_gpus, khs=$khs, shares=$blocks_accepted/$blocks_rejected, uptime=${uptime}s" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
echo "Arrays: hs=$hs_array temp=$temp_array fan=$fan_array" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null

# Output for debugging
echo "stats=$stats" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
echo "khs=$khs" >> "${CUSTOM_LOG_BASENAME}-stats.log" 2>/dev/null
