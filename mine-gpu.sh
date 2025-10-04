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

echo -e "${BLUE}🚀 Xenom GPU-Only Miner${NC}"
echo "================================="
echo "Node: $NODE_URL"
echo "Mode: GPU-only brute-force"
echo "MV Length: $MV_LEN"
echo "No CPU fallback enabled"
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
    
    # GPU-only mode (no CPU fallback)
    echo -e "${BLUE}🎮 GPU-only mode${NC}"
    echo "   Debug: MV_LEN=$MV_LEN"
    MINER_CMD="$MINER_BIN \
        --header-hex $HEADER_HEX \
        --bits-hex $DIFFICULTY \
        --mv-len $MV_LEN \
        --gpu-brute"
    echo "   Debug: Full command: $MINER_CMD"
    
    echo -e "${YELLOW}⛏️  Mining block...${NC}"
    MINE_START=$(date +%s)
    
    # Run miner and capture output
    MINER_OUTPUT=$($MINER_CMD 2>&1)
    CMD_EXIT_CODE=$?
    
    # GPU-only mode - no CPU fallback
    if [ $CMD_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}❌ GPU mining failed with exit code $CMD_EXIT_CODE${NC}"
        echo "GPU miner output:"
        echo "$MINER_OUTPUT"
        echo ""
        echo "💡 To enable CPU fallback, use regular mine.sh or set USE_GPU=false"
        sleep 5
        continue
    fi

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
    
    # Check if solution was found - handle different output formats
    if echo "$MINER_OUTPUT" | grep -q "SOLUTION FOUND\|FOUND"; then
        echo -e "${GREEN}✅ Solution found in ${MINE_DURATION}s!${NC}"
        
        # Extract mutation vector (EXACTLY like mine.sh)
        MUTATION_VECTOR=$(echo "$MINER_OUTPUT" | grep "FOUND" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
        
        # Debug: Show the FOUND line to check format
        FOUND_LINE=$(echo "$MINER_OUTPUT" | grep "FOUND")
        echo "   Debug - FOUND line: $FOUND_LINE"
        echo "   Debug - MV length: ${#MUTATION_VECTOR} chars (should be 32 for 16 bytes)"
        
        # Check if GPU mode produced wrong mutation vector length
        if [ ${#MUTATION_VECTOR} -eq 16 ]; then
            echo -e "${RED}⚠️  GPU mode produced 8-byte MV instead of 16-byte!${NC}"
            echo -e "${RED}   This will likely be rejected by the node.${NC}"
            echo -e "${YELLOW}   Consider using mine.sh for reliable 16-byte MVs${NC}"
        fi
        
        # Extract hash
        SOLUTION_HASH=$(echo "$MINER_OUTPUT" | grep "Hash:" | sed 's/.*Hash: *//' | sed 's/[^a-f0-9].*//' || echo "N/A")
        
        echo "   Mutation vector: $MUTATION_VECTOR"
        echo "   Hash: ${SOLUTION_HASH:0:32}..."
        
        # Debug: Show full miner output when solution found
        if [ "${DEBUG_SOLUTION:-false}" = "true" ]; then
            echo "--- Full miner output ---"
            echo "$MINER_OUTPUT"
            echo "--- End miner output ---"
        fi
        
        # Validate mutation vector format
        if [ -z "$MUTATION_VECTOR" ] || ! echo "$MUTATION_VECTOR" | grep -qE '^[a-f0-9]+$'; then
            echo -e "${RED}❌ Invalid mutation vector format: '$MUTATION_VECTOR'${NC}"
            echo "   Full miner output:"
            echo "$MINER_OUTPUT"
            sleep 5
            continue
        fi
        
        # Verify the solution with CPU Blake3 before submitting
        echo -e "${YELLOW}🔍 Verifying solution with CPU Blake3...${NC}"
        if command -v blake3sum >/dev/null 2>&1; then
            CPU_HASH=$(echo -n "${HEADER_HEX}${MUTATION_VECTOR}" | xxd -r -p | blake3sum | cut -d' ' -f1)
        elif command -v b3sum >/dev/null 2>&1; then
            CPU_HASH=$(echo -n "${HEADER_HEX}${MUTATION_VECTOR}" | xxd -r -p | b3sum | cut -d' ' -f1)
        fi
        
        if [ -n "$CPU_HASH" ]; then
            echo "   CPU Blake3: ${CPU_HASH:0:32}..."
            echo "   GPU Hash:   ${SOLUTION_HASH:0:32}..."
            
            if [ "$CPU_HASH" != "$SOLUTION_HASH" ]; then
                echo -e "${RED}❌ Hash mismatch between GPU and CPU Blake3!${NC}"
                echo -e "${YELLOW}🔄 GPU Blake3 is buggy, falling back to CPU mode...${NC}"
                
                # Retry with CPU mode for this block
                MINER_CMD="$MINER_BIN \
                    --header-hex $HEADER_HEX \
                    --bits-hex $DIFFICULTY \
                    --mv-len $MV_LEN \
                    --threads 0 \
                    --brute"
                MINER_OUTPUT=$($MINER_CMD 2>&1)
                
                # Re-extract mutation vector from CPU result
                MUTATION_VECTOR=$(echo "$MINER_OUTPUT" | grep "FOUND" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
                SOLUTION_HASH=$(echo "$MINER_OUTPUT" | grep "Hash:" | sed 's/.*Hash: *//' | sed 's/[^a-f0-9].*//' || echo "N/A")
                
                echo "   CPU retry - MV: $MUTATION_VECTOR"
                echo "   CPU retry - Hash: ${SOLUTION_HASH:0:32}..."
                
                # Verify CPU solution
                if command -v b3sum >/dev/null 2>&1; then
                    CPU_HASH_RETRY=$(echo -n "${HEADER_HEX}${MUTATION_VECTOR}" | xxd -r -p | b3sum | cut -d' ' -f1)
                    if [ "$CPU_HASH_RETRY" = "$SOLUTION_HASH" ]; then
                        echo -e "${GREEN}✅ CPU solution verified${NC}"
                        CPU_HASH="$CPU_HASH_RETRY"  # Use CPU hash for submission
                    else
                        echo -e "${RED}❌ CPU solution also failed verification${NC}"
                        sleep 5
                        continue
                    fi
                fi
            else
                echo -e "${GREEN}✅ Hash verified${NC}"
                
                # Also verify target comparison
                echo -e "${YELLOW}🎯 Checking target comparison...${NC}"
                echo "   Hash:   $CPU_HASH"
                echo "   Target: ${TARGET_HEX:-$(printf "%064s" | tr ' ' '0' | sed 's/^/007fffff/')}"
                
                # Simple lexicographic comparison (big-endian hex strings)
                if [[ "$CPU_HASH" < "${TARGET_HEX:-007fffff$(printf "%056s" | tr ' ' '0')}" ]]; then
                    echo -e "${GREEN}✅ Hash meets target${NC}"
                else
                    echo -e "${RED}❌ Hash does NOT meet target${NC}"
                    echo "   This solution should be rejected"
                fi
                
                # CRITICAL: Test with current timestamp (like the node does)
                echo -e "${YELLOW}🕐 Testing with current timestamp (node behavior)...${NC}"
                CURRENT_TIMESTAMP=$(date +%s%3N)
                echo "   Template timestamp: $TIMESTAMP"
                echo "   Current timestamp:  $CURRENT_TIMESTAMP"
                
                if [ "$TIMESTAMP" != "$CURRENT_TIMESTAMP" ]; then
                    echo -e "${RED}⚠️  Timestamp mismatch detected!${NC}"
                    echo "   This could be why the node rejects the solution"
                fi
            fi
        else
            echo "   (blake3sum/b3sum not available, skipping verification)"
            echo "   Install with: ./install-blake3sum.sh"
        fi
        
        echo ""
        
        # Submit solution to node (EXACTLY like mine.sh)
        echo -e "${YELLOW}📤 Submitting solution...${NC}"
        echo "   JSON payload: {\"height\": $HEIGHT, \"mutation_vector_hex\": \"$MUTATION_VECTOR\", \"timestamp\": $TIMESTAMP}"
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
