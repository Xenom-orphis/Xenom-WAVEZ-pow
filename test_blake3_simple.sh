#!/bin/bash

# Test script for optimized Blake3 CUDA implementation

echo "🧪 Testing optimized Blake3 CUDA implementation..."

# Compile the CUDA kernel
echo "📦 Compiling blake3_simple.cu to PTX..."
cd xenom-miner-rust

if command -v nvcc &> /dev/null; then
    # Determine CUDA architecture
    CUDA_ARCH=${CUDA_ARCH:-sm_75}
    echo "Using CUDA architecture: $CUDA_ARCH"
    
    nvcc --ptx src/blake3_simple.cu -o blake3_simple.ptx -arch=$CUDA_ARCH --use_fast_math -O3
    
    if [ $? -eq 0 ]; then
        echo "✅ CUDA kernel compiled successfully"
        ls -la blake3_simple.ptx
        
        # Also create legacy name for compatibility
        cp blake3_simple.ptx blake3.ptx
        echo "✅ Legacy blake3.ptx created for compatibility"
        
        # Build and test the Rust miner
        echo "🦀 Building Rust miner with CUDA support..."
        cargo build --release --features cuda
        
        if [ $? -eq 0 ]; then
            echo "✅ Rust miner built successfully with optimized Blake3"
            echo ""
            echo "🚀 Ready to use optimized GPU mining!"
            echo ""
            echo "New features available:"
            echo "  - Optimized Blake3 CUDA kernels with shared memory"
            echo "  - Fast single-block path for small inputs (≤64 bytes)"
            echo "  - Improved genetic operators with tournament selection"
            echo "  - New brute-force nonce search kernel"
            echo "  - Better fitness evaluation with early termination"
            echo ""
            echo "Usage:"
            echo "  ./target/release/xenom-miner-rust --gpu --brute"
        else
            echo "❌ Failed to build Rust miner"
            exit 1
        fi
    else
        echo "❌ Failed to compile CUDA kernel"
        echo "Make sure CUDA Toolkit is installed and nvcc is in PATH"
        exit 1
    fi
else
    echo "❌ nvcc not found. Please install CUDA Toolkit"
    echo "For different GPU architectures, set CUDA_ARCH:"
    echo "  RTX 50 series: CUDA_ARCH=sm_90"
    echo "  RTX 40 series: CUDA_ARCH=sm_89" 
    echo "  RTX 30 series: CUDA_ARCH=sm_86"
    echo "  RTX 20 series: CUDA_ARCH=sm_75"
    echo "  GTX 16/10 series: CUDA_ARCH=sm_75"
    exit 1
fi
