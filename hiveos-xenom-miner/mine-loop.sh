#!/bin/bash
# Main mining loop for Xenom PoW miner

# Variables should be set by h-run.sh
NODE_URL="${NODE_URL:-http://eu.losmuchachos.digital:36669}"
MINER_BIN="${MINER_BIN:-./xenom-miner-rust/target/release/xenom-miner-rust}"
MINER_ADDRESS="${MINER_ADDRESS:-}"
THREADS="${THREADS:-0}"
MV_LEN="${MV_LEN:-16}"

# Stats tracking
BLOCKS_FOUND=0
BLOCKS_ACCEPTED=0
BLOCKS_REJECTED=0
START_TIME=$(date +%s)

while true; do
    echo "----------------------------------------"
    echo "Fetching mining template..."
    
    # Build template URL with optional miner address
    TEMPLATE_URL="$NODE_URL/mining/template"
    if [ ! -z "$MINER_ADDRESS" ]; then
        TEMPLATE_URL="$TEMPLATE_URL?address=$MINER_ADDRESS"
    fi
    
    # Get new PoW block template from node
    TEMPLATE=$(curl -s "$TEMPLATE_URL")
    
    if [ -z "$TEMPLATE" ] || [ "$TEMPLATE" = "null" ]; then
        echo "❌ Failed to fetch mining template. Is the node running?"
        sleep 5
        continue
    fi
    
    # Extract template fields
    HEIGHT=$(echo "$TEMPLATE" | jq -r .height)
    HEADER=$(echo "$TEMPLATE" | jq -r .header_prefix_hex)
    TIMESTAMP=$(echo "$TEMPLATE" | jq -r .timestamp)
    DIFFICULTY=$(echo "$TEMPLATE" | jq -r .difficulty_bits)
    REWARD_ADDRESS=$(echo "$TEMPLATE" | jq -r .miner_address)
    
    if [ -z "$HEADER" ] || [ "$HEADER" = "null" ] || [ -z "$HEIGHT" ]; then
        echo "❌ Invalid template response. Is the node running?"
        sleep 5
        continue
    fi
    
    echo "Mining new block $HEIGHT (timestamp: $TIMESTAMP)"
    echo "Header prefix: ${HEADER:0:32}..."
    echo "Difficulty: 0x$DIFFICULTY"
    echo "Reward to: $REWARD_ADDRESS"
    echo "Stats: Found=$BLOCKS_FOUND Accepted=$BLOCKS_ACCEPTED Rejected=$BLOCKS_REJECTED"
    
    # Use brute-force mode (MUCH faster than genetic algorithm!)
    RESULT=$($MINER_BIN \
        --header-hex "$HEADER" \
        --bits-hex $DIFFICULTY \
        --mv-len $MV_LEN \
        --threads $THREADS \
        --brute 2>&1)
    
    if echo "$RESULT" | grep -q "FOUND"; then
        MV=$(echo "$RESULT" | grep "FOUND" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
        BLOCKS_FOUND=$((BLOCKS_FOUND + 1))
        echo "✅ Found solution: $MV"
        
        # Submit the mined block
        echo "📤 Submitting solution to node..."
        SUBMIT_RESULT=$(curl -s -X POST "$NODE_URL/mining/submit" \
            -H "Content-Type: application/json" \
            -d "{\"height\": $HEIGHT, \"mutation_vector_hex\": \"$MV\", \"timestamp\": $TIMESTAMP}")
        
        SUCCESS=$(echo "$SUBMIT_RESULT" | jq -r .success)
        MESSAGE=$(echo "$SUBMIT_RESULT" | jq -r .message)
        HASH=$(echo "$SUBMIT_RESULT" | jq -r .hash)
        
        if [ "$SUCCESS" = "true" ]; then
            BLOCKS_ACCEPTED=$((BLOCKS_ACCEPTED + 1))
            echo "✅ Solution accepted!"
            echo "   Message: $MESSAGE"
            echo "   Block hash: $HASH"
        else
            BLOCKS_REJECTED=$((BLOCKS_REJECTED + 1))
            echo "❌ Solution rejected: $MESSAGE"
        fi
    else
        echo "❌ No solution found, retrying..."
    fi
    
    sleep 2
done
