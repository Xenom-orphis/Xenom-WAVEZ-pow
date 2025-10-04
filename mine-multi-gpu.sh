#!/bin/bash
# Run miner on all available GPUs in parallel

NODE_URL="${NODE_URL:-http://localhost:36669}"
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"
POPULATION="${POPULATION:-16384}"
BATCHES="${BATCHES:-10000}"
MV_LEN="${MV_LEN:-16}"

# Check if miner exists
if [ ! -f "$MINER_BIN" ]; then
    echo "❌ Miner binary not found. Build it first:"
    echo "   cd xenom-miner-rust && cargo build --release --features cuda && cd .."
    exit 1
fi

# Detect number of GPUs
if command -v nvidia-smi &> /dev/null; then
    NUM_GPUS=$(nvidia-smi -L | wc -l)
    echo "🎮 Detected $NUM_GPUS GPU(s)"
else
    echo "⚠️  nvidia-smi not found, assuming 1 GPU"
    NUM_GPUS=1
fi

# Kill any existing miners
pkill -f "xenom-miner-rust.*--mine-loop" 2>/dev/null

# Start miner for each GPU
echo "🚀 Starting miners on $NUM_GPUS GPU(s)..."
for ((i=0; i<NUM_GPUS; i++)); do
    LOG_FILE="gpu${i}_miner.log"
    echo "   GPU $i -> $LOG_FILE"
    
    nohup "$MINER_BIN" \
        --mine-loop \
        --node-url "$NODE_URL" \
        --gpu \
        --gpu-brute \
        --gpu-id "$i" \
        --population "$POPULATION" \
        --batches "$BATCHES" \
        --mv-len "$MV_LEN" \
        > "$LOG_FILE" 2>&1 &
    
    # Small delay to avoid race conditions
    sleep 0.5
done

echo ""
echo "✅ All miners started!"
echo ""
echo "Monitor with:"
echo "  tail -f gpu0_miner.log"
echo "  tail -f gpu1_miner.log"
echo "  ..."
echo ""
echo "Stop all miners:"
echo "  pkill -f 'xenom-miner-rust.*--mine-loop'"
