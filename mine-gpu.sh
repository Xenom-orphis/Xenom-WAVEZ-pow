#!/bin/bash
# GPU-accelerated mining script for Xenom PoW blockchain
# Integrates with the existing node REST API

# Don't exit on errors - we want to keep mining in a loop
set +e

# Configuration
NODE_URL="${NODE_URL:-http://eu.losmuchachos.digital:36669}"
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"
USE_GPU="${USE_GPU:-true}"
MV_LEN="${MV_LEN:-16}"  # Same as mine.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if miner binary exists
if [ ! -f "$MINER_BIN" ]; then
    echo -e "${YELLOW}⚠️  Miner binary not found. Building...${NC}"
    cd xenom-miner-rust
    if [ "$USE_GPU" = "true" ] && command -v nvcc &> /dev/null; then
        echo -e "${BLUE}Building with CUDA support...${NC}"
        cargo build --release --features cuda
    else
        echo -e "${BLUE}Building CPU-only version...${NC}"
        cargo build --release
    fi
    cd ..
    echo -e "${GREEN}✅ Build complete${NC}"
fi

# Optional: force rebuild each run to pick up latest changes
if [ "${ALWAYS_REBUILD:-false}" = "true" ]; then
    echo -e "${BLUE}Rebuilding miner (ALWAYS_REBUILD=true)...${NC}"
    pushd xenom-miner-rust >/dev/null
    if [ "$USE_GPU" = "true" ] && command -v nvcc &> /dev/null; then
        cargo build --release --features cuda
    else
        cargo build --release
    fi
    popd >/dev/null
fi

echo "🚀 Xenom GPU Miner"
echo "Node: $NODE_URL"
echo ""

# Mining loop
BLOCK_COUNT=0
START_TIME=$(date +%s)

while true; do
    echo "----------------------------------------"
    echo "Fetching mining template..."
    
    # Build template URL with optional miner address (like mine.sh)
    TEMPLATE_URL="$NODE_URL/mining/template"
    if [ ! -z "$MINER_ADDRESS" ]; then
        TEMPLATE_URL="$TEMPLATE_URL?address=$MINER_ADDRESS"
    fi
    
    # Get mining template from node
    TEMPLATE=$(curl -s "$TEMPLATE_URL" || echo "")
    
    if [ -z "$TEMPLATE" ] || [ "$TEMPLATE" = "null" ]; then
        echo "❌ Failed to fetch mining template. Is the node running?"
        sleep 5
        continue
    fi
    
    # Parse template using jq
    HEIGHT=$(echo "$TEMPLATE" | jq -r .height)
    HEADER_HEX=$(echo "$TEMPLATE" | jq -r .header_prefix_hex)
    DIFFICULTY=$(echo "$TEMPLATE" | jq -r .difficulty_bits)
    TARGET_HEX=$(echo "$TEMPLATE" | jq -r .target_hex)
    TIMESTAMP=$(echo "$TEMPLATE" | jq -r .timestamp)
    if [ -z "$HEADER_HEX" ] || [ "$HEADER_HEX" = "null" ] || [ -z "$DIFFICULTY" ]; then
        echo "❌ Invalid template response"
        sleep 5
        continue
    fi
    
    echo "Mining new block $HEIGHT (timestamp: $TIMESTAMP)"
    echo "Header prefix: ${HEADER_HEX:0:32}..."
    echo "Difficulty: 0x$DIFFICULTY"
    
    # GPU brute-force mode (force GPU, no verification)
    MINE_START=$(date +%s)
    
    echo "⛏️  Mining with GPU only..."
    export SKIP_GPU_VERIFICATION=1
    RESULT=$($MINER_BIN \
        --header-hex $HEADER_HEX \
        --bits-hex $DIFFICULTY \
        --mv-len $MV_LEN \
        --gpu \
        --gpu-id 0 \
        --batches 40000 \
        --gpu-brute 2>&1)
    
    CMD_EXIT_CODE=$?
    echo "$RESULT"
    if echo "$RESULT" | grep -q "FOUND"; then
        MUTATION_VECTOR=$(echo "$RESULT" | grep "FOUND" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
        echo "✅ Found solution: $MUTATION_VECTOR"
        
        # Submit the mined block
        echo "📤 Submitting solution to node..."
        SUBMIT_RESULT=$(curl -s -X POST "$NODE_URL/mining/submit" \
            -H "Content-Type: application/json" \
            -d "{\"height\": $HEIGHT, \"mutation_vector_hex\": \"$MUTATION_VECTOR\", \"timestamp\": $TIMESTAMP}")
        
        SUCCESS=$(echo "$SUBMIT_RESULT" | jq -r .success)
        MESSAGE=$(echo "$SUBMIT_RESULT" | jq -r .message)
        HASH=$(echo "$SUBMIT_RESULT" | jq -r .hash)
        
        if [ "$SUCCESS" = "true" ]; then
            echo "✅ Solution accepted!"
            echo "   Message: $MESSAGE"
            echo "   Block hash: $HASH"
        else
            echo "❌ Solution rejected: $MESSAGE"
        fi
    else
        echo "No solution found, trying next template..."
    fi
    
    # Brief pause before fetching next template
    sleep 2
done
