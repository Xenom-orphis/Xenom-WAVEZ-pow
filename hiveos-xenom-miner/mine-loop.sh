#!/bin/bash
# Main mining loop for Xenom PoW miner (GPU mode)

# Variables should be set by h-run.sh
NODE_URL="${NODE_URL:-http://eu.losmuchachos.digital:36669}"
MINER_BIN="${MINER_BIN:-./xenom-miner-rust/target/release/xenom-miner-rust}"
MINER_ADDRESS="${MINER_ADDRESS:-}"
USE_GPU="${USE_GPU:-true}"
GPU_ID="${GPU_ID:-0}"
MULTI_GPU="${MULTI_GPU:-true}"
MV_LEN="${MV_LEN:-16}"

echo "🚀 Starting Xenom GPU Miner"
echo "   Node URL: $NODE_URL"
echo "   Miner Address: ${MINER_ADDRESS:-Node wallet (default)}"
echo "   GPU Mode: Enabled"
echo "   Multi-GPU: $MULTI_GPU"
echo "   MV Length: $MV_LEN"
echo ""

# Build miner command with --mine-loop mode
MINER_CMD="$MINER_BIN --mine-loop --node-url $NODE_URL --gpu --gpu-brute --mv-len $MV_LEN"

# Add miner address if provided
if [ ! -z "$MINER_ADDRESS" ]; then
    MINER_CMD="$MINER_CMD --miner-address $MINER_ADDRESS"
fi

# Add GPU ID if not multi-GPU
if [ "$MULTI_GPU" != "true" ]; then
    MINER_CMD="$MINER_CMD --gpu-id $GPU_ID"
fi

echo "🎮 Running: $MINER_CMD"
echo ""

# Run the miner (it handles everything internally)
exec $MINER_CMD
