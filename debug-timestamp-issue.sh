#!/bin/bash

echo "🔍 Debugging timestamp issue between mine.sh and mine-gpu.sh"

# Get a fresh template
echo "📡 Fetching fresh template..."
TEMPLATE=$(curl -s "http://eu.losmuchachos.digital:36669/mining/template?address=3MyWalletAddressHere123456789xyz")

HEIGHT=$(echo "$TEMPLATE" | jq -r .height)
HEADER_HEX=$(echo "$TEMPLATE" | jq -r .header_prefix_hex)
DIFFICULTY=$(echo "$TEMPLATE" | jq -r .difficulty_bits)
TARGET_HEX=$(echo "$TEMPLATE" | jq -r .target_hex)
TIMESTAMP=$(echo "$TEMPLATE" | jq -r .timestamp)

echo "Template details:"
echo "  Height: $HEIGHT"
echo "  Header: ${HEADER_HEX:0:32}..."
echo "  Difficulty: 0x$DIFFICULTY"
echo "  Target: ${TARGET_HEX:0:16}..."
echo "  Timestamp: $TIMESTAMP"
echo ""

# Test with a known mutation vector from mine.sh success
TEST_MV="1d124556d69588214a316dfe39246112"  # From your successful mine.sh run

echo "🧪 Testing with successful mine.sh mutation vector: $TEST_MV"

# Test Blake3 hash construction
if command -v b3sum >/dev/null 2>&1; then
    HASH_RESULT=$(echo -n "${HEADER_HEX}${TEST_MV}" | xxd -r -p | b3sum | cut -d' ' -f1)
    echo "Blake3 hash: $HASH_RESULT"
    
    # Check if it meets target
    if [[ "$HASH_RESULT" < "$TARGET_HEX" ]]; then
        echo "✅ Hash meets target"
    else
        echo "❌ Hash does NOT meet target"
    fi
    
    # Test submission
    echo ""
    echo "🚀 Testing submission to node..."
    SUBMIT_RESULT=$(curl -s -X POST "http://eu.losmuchachos.digital:36669/mining/submit" \
        -H "Content-Type: application/json" \
        -d "{\"height\": $HEIGHT, \"mutation_vector_hex\": \"$TEST_MV\", \"timestamp\": $TIMESTAMP}")
    
    SUCCESS=$(echo "$SUBMIT_RESULT" | jq -r .success)
    MESSAGE=$(echo "$SUBMIT_RESULT" | jq -r .message)
    
    if [ "$SUCCESS" = "true" ]; then
        echo "✅ Submission accepted!"
        echo "   Message: $MESSAGE"
    else
        echo "❌ Submission rejected: $MESSAGE"
    fi
else
    echo "❌ b3sum not available. Install with: ./install-blake3sum.sh"
fi

echo ""
echo "💡 Key insight: If this test fails, it means the GPU miner"
echo "   is using a different timestamp when computing the hash"
echo "   than what it's submitting to the node."
