#!/bin/bash

NODE_URL="${NODE_URL:-http://eu.losmuchachos.digital:36669}"  # Local node by default
MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"
MINER_ADDRESS="${MINER_ADDRESS:-}"  # Optional: Your wallet address for rewards

# Check if miner binary exists
if [ ! -f "$MINER_BIN" ]; then
    echo "Building miner..."
    cd xenom-miner-rust && cargo build --release && cd ..
fi

# Show reward destination
if [ ! -z "$MINER_ADDRESS" ]; then
    echo "💰 Mining rewards will go to: $MINER_ADDRESS"
else
    echo "💰 Mining rewards will go to: Node wallet (default)"
fi
echo ""

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
        
        # Build submission JSON with optional miner address
        if [ ! -z "$MINER_ADDRESS" ]; then
            SUBMIT_JSON="{\"height\": $HEIGHT, \"mutation_vector_hex\": \"$MV\", \"timestamp\": $TIMESTAMP, \"miner_address\": \"$MINER_ADDRESS\"}"
        else
            SUBMIT_JSON="{\"height\": $HEIGHT, \"mutation_vector_hex\": \"$MV\", \"timestamp\": $TIMESTAMP}"
        fi
        
        SUBMIT_RESULT=$(curl -s -X POST "$NODE_URL/mining/submit" \
            -H "Content-Type: application/json" \
            -d "$SUBMIT_JSON")
        
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
