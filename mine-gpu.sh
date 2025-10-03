#!/bin/bash
# GPU-accelerated mining script for Xenom PoW blockchain
# Integrates with the existing node REST API

set -e

# Configuration
NODE_URL="${NODE_URL:-http://localhost:36669}"
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"
USE_GPU="${USE_GPU:-true}"
POPULATION="${POPULATION:-8192}"
GENERATIONS="${GENERATIONS:-1000}"
MUTATION_RATE="${MUTATION_RATE:-0.01}"
MV_LEN="${MV_LEN:-16}"
BATCHES="${BATCHES:-5000}"

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
echo "Population: $POPULATION"
echo "Generations: $GENERATIONS"
echo "Mutation Rate: $MUTATION_RATE"
echo "MV Length: $MV_LEN"
echo "Mode: GPU brute-force"
echo "Batches: $BATCHES"
echo ""

# Mining loop
BLOCK_COUNT=0
START_TIME=$(date +%s)

while true; do
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📡 Fetching mining template...${NC}"
    
    # Get mining template from node
    TEMPLATE=$(curl -s "${NODE_URL}/mining/template" || echo "")
    
    if [ -z "$TEMPLATE" ]; then
        echo -e "${RED}❌ Failed to fetch template from node${NC}"
        echo "   Retrying in 5 seconds..."
        sleep 5
        continue
    fi
    
    # Parse template (API returns header_prefix_hex and difficulty_bits)
    HEADER_HEX=$(echo "$TEMPLATE" | grep -o '"header_prefix_hex":"[^"]*"' | cut -d'"' -f4)
    DIFFICULTY=$(echo "$TEMPLATE" | grep -o '"difficulty_bits":"[^"]*"' | cut -d'"' -f4)
    TIMESTAMP=$(echo "$TEMPLATE" | grep -o '"timestamp":[0-9]*' | cut -d':' -f2)
    
    if [ -z "$HEADER_HEX" ] || [ -z "$DIFFICULTY" ]; then
        echo -e "${RED}❌ Invalid template response${NC}"
        echo "   Response: $TEMPLATE"
        sleep 5
        continue
    fi
    
    echo -e "${GREEN}✅ Template received${NC}"
    echo "   Header length: ${#HEADER_HEX} chars"
    echo "   Difficulty: 0x$DIFFICULTY"
    echo "   Timestamp: $TIMESTAMP"
    echo ""
    
    # Build miner command
    MINER_CMD="$MINER_BIN \
        --header-hex $HEADER_HEX \
        --bits-hex $DIFFICULTY \
        --population $POPULATION \
        --generations $GENERATIONS \
        --mv-len $MV_LEN"
    
    if [ "$USE_GPU" = "true" ]; then
        MINER_CMD="$MINER_CMD --gpu --gpu-brute --batches $BATCHES --mutation-rate $MUTATION_RATE"
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
    
    # Check if solution was found
    if echo "$MINER_OUTPUT" | grep -q "SOLUTION FOUND"; then
        echo -e "${GREEN}✅ Solution found in ${MINE_DURATION}s!${NC}"
        
        # Extract mutation vector
        MUTATION_VECTOR=$(echo "$MINER_OUTPUT" | grep "Mutation vector:" | sed 's/.*Mutation vector: //' | tr -d ' ')
        SOLUTION_HASH=$(echo "$MINER_OUTPUT" | grep "Hash:" | sed 's/.*Hash: //' | tr -d ' ')
        
        echo "   Mutation vector: $MUTATION_VECTOR"
        echo "   Hash: ${SOLUTION_HASH:0:32}..."
        echo ""
        
        # Submit solution to node
        echo -e "${YELLOW}📤 Submitting solution...${NC}"
        SUBMIT_RESPONSE=$(curl -s -X POST "${NODE_URL}/mining/submit" \
            -H "Content-Type: application/json" \
            -d "{\"solution\": \"$MUTATION_VECTOR\"}" || echo "")
        
        if echo "$SUBMIT_RESPONSE" | grep -q "accepted\|success\|Valid"; then
            BLOCK_COUNT=$((BLOCK_COUNT + 1))
            TOTAL_TIME=$(($(date +%s) - START_TIME))
            AVG_TIME=$((TOTAL_TIME / BLOCK_COUNT))
            
            echo -e "${GREEN}🎉 Block accepted!${NC}"
            echo "   Blocks mined: $BLOCK_COUNT"
            echo "   Average time: ${AVG_TIME}s/block"
            echo ""
            
            # Brief pause before next block
            sleep 2
        else
            echo -e "${RED}❌ Solution rejected${NC}"
            echo "   Response: $SUBMIT_RESPONSE"
            echo ""
            sleep 1
        fi
    else
        echo -e "${YELLOW}⏭️  No solution found in ${MINE_DURATION}s, trying next template...${NC}"
        echo ""
        sleep 1
    fi
done
