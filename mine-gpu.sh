#!/bin/bash
# GPU-accelerated mining script for Xenom PoW blockchain
# Integrates with the existing node REST API

# Don't exit on errors - we want to keep mining in a loop
set +e

# Configuration
NODE_URL="${NODE_URL:-http://localhost:36669}"
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

echo -e "${BLUE}🚀 Xenom GPU Miner${NC}"
echo "================================="
echo "Node: $NODE_URL"
echo "GPU Mode: $USE_GPU"
echo "MV Length: $MV_LEN"
echo "Mode: Brute-force"
echo ""

# Mining loop
BLOCK_COUNT=0
START_TIME=$(date +%s)

while true; do
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📡 Fetching mining template...${NC}"
    
    # Build template URL with optional miner address (like mine.sh)
    TEMPLATE_URL="$NODE_URL/mining/template"
    if [ ! -z "$MINER_ADDRESS" ]; then
        TEMPLATE_URL="$TEMPLATE_URL?address=$MINER_ADDRESS"
    fi
    
    # Get mining template from node
    TEMPLATE=$(curl -s "$TEMPLATE_URL" || echo "")
    
    if [ -z "$TEMPLATE" ]; then
        echo -e "${RED}❌ Failed to fetch template from node${NC}"
        echo "   Retrying in 5 seconds..."
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
        echo -e "${RED}❌ Invalid template response${NC}"
        echo "   Response: $TEMPLATE"
        sleep 5
        continue
    fi
    
    echo -e "${GREEN}✅ Template received${NC}"
    echo "   Height: $HEIGHT"
    echo "   Header length: ${#HEADER_HEX} chars"
    echo "   Difficulty: 0x$DIFFICULTY"
    if [ -n "$TARGET_HEX" ] && [ "$TARGET_HEX" != "null" ]; then
        echo "   Target (hex, BE): ${TARGET_HEX:0:16}..."
    fi
    echo "   Timestamp: $TIMESTAMP"
    echo ""
    
    # Build miner command (simplified like mine.sh but with GPU support)
    MINER_CMD="$MINER_BIN \
        --header-hex $HEADER_HEX \
        --bits-hex $DIFFICULTY \
        --mv-len $MV_LEN"
    
    if [ "$USE_GPU" = "true" ]; then
        # Use GPU brute-force mode (similar to --brute but on GPU)
        MINER_CMD="$MINER_CMD --gpu --brute"
    else
        # Use CPU brute-force mode (like mine.sh)
        MINER_CMD="$MINER_CMD --brute --threads 0"
    fi
    
    echo -e "${YELLOW}⛏️  Mining block...${NC}"
    MINE_START=$(date +%s)
    
    # Run miner and capture output
    MINER_OUTPUT=$($MINER_CMD 2>&1)
    CMD_EXIT_CODE=$?

    # Optionally show full miner output (set SHOW_MINER_OUTPUT=true)
    if [ "${SHOW_MINER_OUTPUT:-false}" = "true" ]; then
        echo "--- Miner output begin ---"
        echo "$MINER_OUTPUT"
        echo "--- Miner output end ---"
    fi

    # Surface computed target line for visibility if present
    echo "$MINER_OUTPUT" | grep -m1 -E "Computed target \(hex, big-endian\):" || true
    MINE_EXIT_CODE=$CMD_EXIT_CODE
    
    MINE_END=$(date +%s)
    MINE_DURATION=$((MINE_END - MINE_START))
    
    if [ $MINE_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}❌ Miner failed with exit code $MINE_EXIT_CODE${NC}"
        echo "$MINER_OUTPUT"
        sleep 5
        continue
    fi
    
    # Check if solution was found (using same format as mine.sh)
    if echo "$MINER_OUTPUT" | grep -q "FOUND"; then
        echo -e "${GREEN}✅ Solution found in ${MINE_DURATION}s!${NC}"
        
        # Extract mutation vector (same format as mine.sh)
        MUTATION_VECTOR=$(echo "$MINER_OUTPUT" | grep "FOUND" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
        SOLUTION_HASH=$(echo "$MINER_OUTPUT" | grep "Hash:" | sed 's/.*Hash: //' | tr -d ' ' || echo "N/A")
        
        echo "   Mutation vector: $MUTATION_VECTOR"
        echo "   Hash: ${SOLUTION_HASH:0:32}..."
        echo ""
        
        # Submit solution to node
        echo -e "${YELLOW}📤 Submitting solution...${NC}"
        SUBMIT_RESULT=$(curl -s -X POST "${NODE_URL}/mining/submit" \
            -H "Content-Type: application/json" \
            -d "{\"height\": $HEIGHT, \"mutation_vector_hex\": \"$MUTATION_VECTOR\", \"timestamp\": $TIMESTAMP}")
        
        SUCCESS=$(echo "$SUBMIT_RESULT" | jq -r .success)
        MESSAGE=$(echo "$SUBMIT_RESULT" | jq -r .message)
        HASH=$(echo "$SUBMIT_RESULT" | jq -r .hash)
        
        if [ "$SUCCESS" = "true" ]; then
            echo -e "${GREEN}✅ Solution accepted!${NC}"
            echo "   Message: $MESSAGE"
            echo "   Block hash: $HASH"
        else
            echo -e "${RED}❌ Solution rejected: $MESSAGE${NC}"
        fi
    else
        echo -e "${YELLOW}⏭️  No solution found in ${MINE_DURATION}s, trying next template...${NC}"
        echo ""
    fi
    
    # Brief pause before fetching next template
    sleep 2
done
