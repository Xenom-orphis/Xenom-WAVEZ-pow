#!/bin/bash
# Optimized GPU mining loop - all logic in Rust for maximum performance

NODE_URL="${NODE_URL:-http://localhost:36669}"
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"
POPULATION="${POPULATION:-16384}"  # Larger population for better GPU utilization
BATCHES="${BATCHES:-10000}"  # More batches per attempt
MV_LEN="${MV_LEN:-16}"

# Check if miner exists
if [ ! -f "$MINER_BIN" ]; then
    echo "⚠️  Building miner with CUDA support..."
    cd xenom-miner-rust
    cargo build --release --features cuda
    cd ..
fi

echo "🚀 Starting Rust-native GPU mining loop"
echo "   Node: $NODE_URL"
echo "   Population: $POPULATION"
echo "   Batches: $BATCHES"
echo ""

# Run the miner in loop mode - all logic happens in Rust
exec "$MINER_BIN" \
    --mine-loop \
    --node-url "$NODE_URL" \
    --gpu \
    --gpu-brute \
    --population "$POPULATION" \
    --batches "$BATCHES" \
    --mv-len "$MV_LEN"
