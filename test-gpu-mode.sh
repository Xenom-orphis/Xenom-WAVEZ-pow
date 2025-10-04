#!/bin/bash

echo "🧪 Testing GPU mode with automatic fallback..."

# Set environment for GPU testing
export USE_GPU=true
export MINER_ADDRESS="3MyWalletAddressHere123456789xyz"
export DEBUG_SOLUTION=true

echo "Configuration:"
echo "  USE_GPU=$USE_GPU"
echo "  MINER_ADDRESS=$MINER_ADDRESS"
echo ""

# Run one mining attempt
echo "🚀 Starting GPU mining test (will timeout after 30 seconds)..."
timeout 30s ./mine-gpu.sh || echo "Test completed or timed out"

echo ""
echo "💡 What to expect:"
echo "  1. If CUDA is available: GPU mining attempt, may fallback to CPU"
echo "  2. If CUDA not available: Automatic fallback to CPU mode"
echo "  3. CPU mode should produce 32-char (16-byte) mutation vectors"
echo "  4. Solutions should be accepted by the node"
