#!/usr/bin/env bash
# This script generates the miner configuration file
# HiveOS variables available: $CUSTOM_URL, $CUSTOM_TEMPLATE, $CUSTOM_USER_CONFIG, etc.

# Set default config filename if not provided by HiveOS
if [[ -z $CUSTOM_CONFIG_FILENAME ]]; then
    CUSTOM_CONFIG_FILENAME="/hive/miners/custom/xenom-miner/xenom.conf"
    echo "Using default config file: $CUSTOM_CONFIG_FILENAME"
fi

[[ -z $CUSTOM_URL ]] && echo -e "${YELLOW}CUSTOM_URL is empty${NOCOLOR}" && return 1

# Parse pool URL (node URL)
NODE_URL="$CUSTOM_URL"

# Get miner address from template or user config
MINER_ADDRESS=""
if [[ ! -z $CUSTOM_TEMPLATE ]]; then
    MINER_ADDRESS="$CUSTOM_TEMPLATE"
fi

# Default values
THREADS=0
MV_LEN=16
USE_GPU=true
GPU_ID=0
MULTI_GPU=true
GPU_BATCHES=40000

# User config can override settings (JSON format expected)
if [[ ! -z $CUSTOM_USER_CONFIG ]]; then
    # Try to parse JSON user config
    MINER_ADDRESS=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.miner_address // empty' 2>/dev/null)
    [[ -z $MINER_ADDRESS ]] && MINER_ADDRESS=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.address // empty' 2>/dev/null)
    
    # Parse GPU settings (use true as default for GPU settings)
    THREADS=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.threads // 0' 2>/dev/null)
    MV_LEN=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.mv_len // 16' 2>/dev/null)
    USE_GPU=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.use_gpu // true' 2>/dev/null)
    GPU_ID=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.gpu_id // 0' 2>/dev/null)
    MULTI_GPU=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.multi_gpu // true' 2>/dev/null)
    GPU_BATCHES=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.gpu_batches // 40000' 2>/dev/null)
fi

# Create config file
cat > $CUSTOM_CONFIG_FILENAME <<EOF
# Xenom Miner Configuration
NODE_URL=$NODE_URL
MINER_ADDRESS=$MINER_ADDRESS
THREADS=$THREADS
MV_LEN=$MV_LEN
USE_GPU=$USE_GPU
GPU_ID=$GPU_ID
MULTI_GPU=$MULTI_GPU
GPU_BATCHES=$GPU_BATCHES
EOF

echo "Xenom miner config generated:"
cat $CUSTOM_CONFIG_FILENAME
