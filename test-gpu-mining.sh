#!/bin/bash

echo "🧪 Testing GPU mining setup..."

# Set environment variables for testing
export MINER_ADDRESS="3MyWalletAddressHere123456789xyz"
export USE_GPU=true
export MV_LEN=16

# Check if node is running
echo "📡 Checking node connection..."
NODE_STATUS=$(curl -s "http://localhost:36669/mining/template?address=$MINER_ADDRESS" || echo "")

if [ -z "$NODE_STATUS" ]; then
    echo "❌ Node not responding. Please start the node first:"
    echo "   ./start-node.sh"
    exit 1
fi

echo "✅ Node is running"

# Check if miner binary exists
if [ ! -f "./xenom-miner-rust/target/release/xenom-miner-rust" ]; then
    echo "🔨 Building miner..."
    cd xenom-miner-rust
    if command -v nvcc &> /dev/null; then
        echo "Building with CUDA support..."
        cargo build --release --features cuda
    else
        echo "Building CPU-only version..."
        cargo build --release
    fi
    cd ..
fi

echo "✅ Miner binary ready"

# Test mining template fetch
echo "📋 Testing template fetch..."
TEMPLATE=$(curl -s "http://localhost:36669/mining/template?address=$MINER_ADDRESS")
HEIGHT=$(echo "$TEMPLATE" | jq -r .height)
HEADER_HEX=$(echo "$TEMPLATE" | jq -r .header_prefix_hex)
DIFFICULTY=$(echo "$TEMPLATE" | jq -r .difficulty_bits)

if [ -z "$HEIGHT" ] || [ "$HEIGHT" = "null" ]; then
    echo "❌ Failed to get valid template"
    echo "Response: $TEMPLATE"
    exit 1
fi

echo "✅ Template received:"
echo "   Height: $HEIGHT"
echo "   Header length: ${#HEADER_HEX} chars"
echo "   Difficulty: 0x$DIFFICULTY"

# Test a quick mining run (5 seconds)
echo ""
echo "⛏️  Testing mining for 5 seconds..."
timeout 5s ./mine-gpu.sh || true

echo ""
echo "🎉 GPU mining test complete!"
echo ""
echo "To start full mining:"
echo "   export MINER_ADDRESS=\"3MyWalletAddressHere123456789xyz\""
echo "   ./mine-gpu.sh"
