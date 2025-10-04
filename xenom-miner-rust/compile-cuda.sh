#!/bin/bash
# Compile CUDA kernel to PTX

set -e

echo "🔨 Compiling CUDA kernel..."

# Check if nvcc is available
if ! command -v nvcc &> /dev/null; then
    echo "❌ nvcc not found. Please install CUDA Toolkit."
    exit 1
fi

# Compile to PTX
nvcc --ptx src/blake3.cu -o blake3.ptx \
    -arch=sm_60 \
    --use_fast_math \
    -O3

if [ -f blake3.ptx ]; then
    echo "✅ CUDA kernel compiled successfully: blake3.ptx"
    echo ""
    echo "PTX file location: $(pwd)/blake3.ptx"
    echo ""
    echo "The miner will automatically find this file when run from:"
    echo "  - $(pwd)"
    echo "  - $(dirname $(pwd))"
else
    echo "❌ Compilation failed"
    exit 1
fi
