#!/bin/bash

NODE_URL="http://eu.losmuchachos.digital:36669"  # Main node (seed)
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"

# Check if miner binary exists
if [ ! -f "$MINER_BIN" ]; then
    echo "Building miner..."
    cd xenom-miner-rust && cargo build --release && cd ..
fi

while true; do
    echo "----------------------------------------"
    echo "Fetching mining template..."
    
    # Get new PoW block template from node
    TEMPLATE=$(curl -s "$NODE_URL/mining/template")
    
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
    
    if [ -z "$HEADER" ] || [ "$HEADER" = "null" ] || [ -z "$HEIGHT" ]; then
        echo "❌ Invalid template response. Is the node running?"
        sleep 5
        continue
    fi
    
    echo "Mining new block $HEIGHT (timestamp: $TIMESTAMP)"
    echo "Header prefix: ${HEADER:0:32}..."
    echo "Difficulty: 0x$DIFFICULTY"
    # Use brute-force mode (MUCH faster than genetic algorithm!)
    RESULT=$($MINER_BIN \
        --header-hex "$HEADER" \
        --bits-hex $DIFFICULTY \
        --mv-len 16 \
        --threads 0 \
        --brute 2>&1)
    
    if echo "$RESULT" | grep -q "FOUND"; then
        MV=$(echo "$RESULT" | grep "FOUND" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
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
            echo "✅ Solution accepted!"
            echo "   Message: $MESSAGE"
            echo "   Block hash: $HASH"
        else
            echo "❌ Solution rejected: $MESSAGE"
        fi
    else
        echo "❌ No solution found, retrying..."
    fi
    
    sleep 2
done