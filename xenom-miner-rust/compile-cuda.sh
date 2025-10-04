#!/bin/bash
# Compile CUDA kernel to PTX

set -e

echo "🔨 Compiling CUDA kernel..."

# Check if nvcc is available
if ! command -v nvcc &> /dev/null; then
    echo "❌ nvcc not found. Please install CUDA Toolkit."
    exit 1
fi

# Auto-detect GPU compute capability
ARCH="${CUDA_ARCH:-}"
if [ -z "$ARCH" ]; then
    if command -v nvidia-smi &> /dev/null; then
        # Try to detect GPU compute capability
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
        echo "🎮 Detected GPU: $GPU_NAME"
        
        # Common mappings (use appropriate compute capability)
        case "$GPU_NAME" in
            *"RTX 50"*|*"RTX 5"*|*"B100"*|*"B200"*)
                ARCH="sm_90"  # Blackwell (RTX 50 series)
                ;;
            *"RTX 40"*|*"RTX 4"*|*"H100"*|*"H200"*|*"L40"*)
                ARCH="sm_89"  # Ada Lovelace / Hopper
                ;;
            *"RTX 30"*|*"RTX 3"*|*"A100"*|*"A40"*|*"A30"*|*"A10"*)
                ARCH="sm_86"  # Ampere
                ;;
            *"RTX 20"*|*"RTX 2"*|*"T4"*|*"V100"*|*"Titan V"*)
                ARCH="sm_75"  # Turing / Volta
                ;;
            *"GTX 16"*|*"GTX 1"*|*"P100"*|*"P40"*|*"Titan X"*)
                ARCH="sm_61"  # Pascal
                ;;
            *)
                # Default to sm_75 (Turing/Volta) for broad modern compatibility
                ARCH="sm_75"
                echo "⚠️  Unknown GPU, using sm_75 for compatibility"
                ;;
        esac
        echo "📊 Using compute capability: $ARCH"
    else
        # Default to sm_75 (Turing/Volta) for broad modern compatibility
        ARCH="sm_75"
        echo "⚠️  nvidia-smi not found, using sm_75 for compatibility"
    fi
fi

# Compile to PTX
nvcc --ptx src/blake3.cu -o blake3.ptx \
    -arch=$ARCH \
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
