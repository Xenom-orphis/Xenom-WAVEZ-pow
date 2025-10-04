#!/bin/bash
# Optimized GPU mining loop - all logic in Rust for maximum performance

NODE_URL="${NODE_URL:-http://localhost:36669}"
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"
POPULATION="${POPULATION:-16384}"  # Larger population for better GPU utilization
BATCHES="${BATCHES:-10000}"  # More batches per attempt
MV_LEN="${MV_LEN:-16}"
MULTI_GPU="${MULTI_GPU:-true}"  # Use all GPUs by default
MINER_ADDRESS="${MINER_ADDRESS:-}"  # Optional: Your wallet address for rewards

# Check if miner exists
if [ ! -f "$MINER_BIN" ]; then
    echo "⚠️  Building miner with CUDA support..."
    cd xenom-miner-rust
    cargo build --release --features cuda
    cd ..
fi

echo "🚀 Starting Rust-native GPU mining loop"
echo "   Node: $NODE_URL"
echo "   Population per GPU: $POPULATION"
echo "   Batches: $BATCHES"
echo "   Multi-GPU: $MULTI_GPU"

# Build arguments array
ARGS=(
    "--mine-loop"
    "--node-url" "$NODE_URL"
    "--gpu"
    "--gpu-brute"
    "--population" "$POPULATION"
    "--batches" "$BATCHES"
    "--mv-len" "$MV_LEN"
)

# Add miner address if provided
if [ ! -z "$MINER_ADDRESS" ]; then
    echo "   💰 Mining to: $MINER_ADDRESS"
    ARGS+=("--miner-address" "$MINER_ADDRESS")
else
    echo "   💰 Mining to: Node wallet (default)"
fi
echo ""

# Run the miner in loop mode - all logic happens in Rust
# MULTI_GPU=true will auto-detect and use all available GPUs
export MULTI_GPU
exec "$MINER_BIN" "${ARGS[@]}"
