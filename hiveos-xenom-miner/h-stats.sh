#!/usr/bin/env bash
# This script provides miner statistics in JSON format
# It's included in the agent script, so agent variables are available

# Get stats from log file
LOG_FILE="${CUSTOM_LOG_BASENAME}.log"

# Initialize default values
local hs=0
local blocks_found=0
local blocks_accepted=0
local blocks_rejected=0
local uptime=0
local current_height=0

# Parse the log file for stats
if [[ -f "$LOG_FILE" ]]; then
    # Get uptime from first log entry
    local first_log=$(head -n 1 "$LOG_FILE" 2>/dev/null)
    local start_time=$(date -d "$first_log" +%s 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    uptime=$((current_time - start_time))
    
    # Get latest stats from log
    blocks_found=$(grep -c "Found solution:" "$LOG_FILE" 2>/dev/null || echo 0)
    blocks_accepted=$(grep -c "Solution accepted!" "$LOG_FILE" 2>/dev/null || echo 0)
    blocks_rejected=$(grep -c "Solution rejected:" "$LOG_FILE" 2>/dev/null || echo 0)
    
    # Get current mining height
    current_height=$(grep "Mining new block" "$LOG_FILE" | tail -n 1 | grep -oP 'block \K[0-9]+' 2>/dev/null || echo 0)
    
    # Calculate hashrate based on blocks found
    # This is approximate - actual hashrate depends on difficulty
    if [[ $uptime -gt 0 ]]; then
        # Rough estimate: assume each attempt is ~1000 hashes
        hs=$(echo "scale=2; $blocks_found * 1000 / $uptime" | bc 2>/dev/null || echo 0)
    fi
fi

# Build stats JSON
# Note: Xenom mining doesn't provide per-GPU stats, so we report total only
stats=$(jq -nc \
    --arg hs "$hs" \
    --arg blocks_found "$blocks_found" \
    --arg blocks_accepted "$blocks_accepted" \
    --arg blocks_rejected "$blocks_rejected" \
    --arg uptime "$uptime" \
    --arg height "$current_height" \
    '{
        hs: [$hs],
        hs_units: "hs",
        temp: [],
        fan: [],
        uptime: ($uptime | tonumber),
        ver: "1.0.0",
        ar: [($blocks_accepted | tonumber), ($blocks_rejected | tonumber)],
        algo: "xenom-pow",
        bus_numbers: []
    }')

# Set required variables for HiveOS
khs=$(echo "scale=3; $hs / 1000" | bc 2>/dev/null || echo 0)

# Debug output (will appear in agent logs)
[[ -n "$CUSTOM_LOG_BASENAME" ]] && echo "Xenom stats: khs=$khs, blocks=$blocks_found, accepted=$blocks_accepted, rejected=$blocks_rejected" >> "${CUSTOM_LOG_BASENAME}-stats.log"
