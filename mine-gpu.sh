#!/bin/bash
# GPU-accelerated mining script for Xenom PoW blockchain
# Integrates with the existing node REST API

# Don't exit on errors - we want to keep mining in a loop
set +e

# Configuration
NODE_URL="${NODE_URL:-http://eu.losmuchachos.digital:36669}"
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"
USE_GPU="${USE_GPU:-true}"
MV_LEN="${MV_LEN:-16}"  # Same as mine.sh
GPU_ID="${GPU_ID:-0}"
MULTI_GPU="${MULTI_GPU:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if miner binary exists
if [ ! -f "$MINER_BIN" ]; then
    echo -e "${YELLOW}⚠️  Miner binary not found. Building...${NC}"
    cd xenom-miner-rust
    if [ "$USE_GPU" = "true" ] && command -v nvcc &> /dev/null; then
        echo -e "${BLUE}Building with CUDA support...${NC}"
        cargo build --release --features cuda
    else
        echo -e "${BLUE}Building CPU-only version...${NC}"
        cargo build --release
    fi
    cd ..
    echo -e "${GREEN}✅ Build complete${NC}"
fi

# Optional: force rebuild each run to pick up latest changes
if [ "${ALWAYS_REBUILD:-false}" = "true" ]; then
    echo -e "${BLUE}Rebuilding miner (ALWAYS_REBUILD=true)...${NC}"
    pushd xenom-miner-rust >/dev/null
    if [ "$USE_GPU" = "true" ] && command -v nvcc &> /dev/null; then
        cargo build --release --features cuda
    else
        cargo build --release
    fi
    popd >/dev/null
fi

echo "🚀 Xenom GPU Miner"
echo "Node: $NODE_URL"
echo "🔍 Debug: MULTI_GPU variable = '${MULTI_GPU:-false}'"
if [ "${MULTI_GPU:-false}" = "true" ]; then
    echo "Multi-GPU: Enabled (auto-detect all GPUs)"
    # Set environment variable once for the entire session
    export MULTI_GPU=1
else
    echo "Single GPU: ${GPU_ID:-0}"
fi
echo ""

# Mining loop
BLOCK_COUNT=0
START_TIME=$(date +%s)

# Use mine-loop mode for continuous mining without reinitialization
echo "🚀 Starting continuous GPU mining..."

# Check multi-GPU mode (already set at startup)
if [ "${MULTI_GPU}" = "1" ]; then
    echo "⛏️  Mining with all available GPUs..."
    echo "🔍 Debug: MULTI_GPU=1, no --gpu-id specified (auto-detect mode)"
else
    echo "⛏️  Mining with GPU ${GPU_ID:-0}..."
    echo "🔍 Debug: Single GPU mode, --gpu-id ${GPU_ID:-0}"
fi

export SKIP_GPU_VERIFICATION=1

# Build miner command with mine-loop mode
if [ "${MULTI_GPU}" = "1" ]; then
    # Multi-GPU mode: don't specify gpu-id, let it default to 0 for auto-detection
    MINER_CMD="$MINER_BIN \
        --mine-loop \
        --node-url $NODE_URL \
        --mv-len $MV_LEN \
        --gpu \
        --batches 40000 \
        --gpu-brute"
else
    # Single GPU mode: specify the GPU ID
    MINER_CMD="$MINER_BIN \
        --mine-loop \
        --node-url $NODE_URL \
        --mv-len $MV_LEN \
        --gpu \
        --gpu-id ${GPU_ID:-0} \
        --batches 40000 \
        --gpu-brute"
fi

# Add miner address if provided
if [ ! -z "$MINER_ADDRESS" ]; then
    MINER_CMD="$MINER_CMD --miner-address $MINER_ADDRESS"
fi

echo "🎮 Command: $MINER_CMD"
echo ""

# Run continuous mining (no loop needed - miner handles everything)
exec $MINER_CMD
