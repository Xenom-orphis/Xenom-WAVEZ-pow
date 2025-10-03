#!/bin/bash
# Example GPU mining script for Xenom PoW

set -e

echo "🚀 Xenom GPU Miner - Example Run"
echo "================================="

# Check if CUDA is available
if ! command -v nvcc &> /dev/null; then
    echo "⚠️  Warning: nvcc not found. GPU mining will not work."
    echo "   Install CUDA Toolkit from: https://developer.nvidia.com/cuda-downloads"
    echo ""
    echo "   Falling back to CPU mining..."
    GPU_FLAG=""
else
    echo "✅ CUDA found: $(nvcc --version | grep release)"
    GPU_FLAG="--gpu"
fi

# Example header (replace with actual mining template)
HEADER_HEX="00000001af61d095195ba666c161e028bdeb3df1d1a1227f0650095885f622418e2b9037000000000000000000000000000000000000000000000000000000000000000000000199a6b882ea000000001f00ffff0000000000000000000000"

# Difficulty bits (0x1f00ffff = testnet difficulty)
BITS_HEX="1f00ffff"

echo ""
echo "Configuration:"
echo "  Mode: ${GPU_FLAG:-CPU GA}"
echo "  Population: 8192"
echo "  Generations: 1000"
echo "  Mutation Rate: 0.01"
echo "  MV Length: 16 bytes"
echo ""

# Build first
echo "📦 Building miner..."
if [ -n "$GPU_FLAG" ]; then
    cargo build --release --features cuda
else
    cargo build --release
fi

echo ""
echo "⛏️  Starting mining..."
echo ""

# Run miner
./target/release/xenom-miner-rust \
    --header-hex "$HEADER_HEX" \
    --bits-hex "$BITS_HEX" \
    $GPU_FLAG \
    --population 8192 \
    --generations 1000 \
    --mutation-rate 0.01 \
    --mv-len 16

echo ""
echo "✅ Mining completed!"
