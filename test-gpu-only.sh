#!/bin/bash

echo "🎮 Testing GPU-only mining mode..."

# Check if CUDA is available
if ! command -v nvcc &> /dev/null; then
    echo "❌ CUDA Toolkit not found. GPU-only mode will fail."
    echo "   Install CUDA Toolkit first or use mine.sh for CPU mining"
    echo ""
    echo "🔧 To install CUDA on macOS:"
    echo "   brew install --cask cuda"
    echo ""
    echo "🔧 To install CUDA on Linux:"
    echo "   # Follow NVIDIA CUDA installation guide"
    exit 1
fi

# Check if PTX kernels exist
if [ ! -f "blake3_simple.ptx" ] && [ ! -f "blake3.ptx" ]; then
    echo "📦 CUDA kernels not found. Building..."
    ./test_blake3_simple.sh
fi

# Set environment for GPU-only testing
export MINER_ADDRESS="3MyWalletAddressHere123456789xyz"
export DEBUG_SOLUTION=true

echo "🚀 Starting GPU-only mining test..."
echo "   This will use ONLY GPU acceleration"
echo "   No CPU fallback will be used"
echo ""

# Run one mining attempt with timeout
timeout 60s ./mine-gpu.sh || echo "Test completed or timed out"

echo ""
echo "💡 Expected behavior:"
echo "  ✅ GPU kernels loaded successfully"
echo "  ✅ GPU mining finds solutions"
echo "  ⚠️  May produce 8-byte MVs (will warn but continue)"
echo "  ❌ If GPU fails, mining stops (no CPU fallback)"
