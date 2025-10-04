#!/bin/bash

# Debug script to test miner output parsing

echo "🔍 Testing miner output parsing..."

# Sample miner outputs to test parsing
TEST_OUTPUTS=(
    "✅ SOLUTION FOUND!
Mutation vector: abcd1234567890ef
Hash: 0060229f9685a09afdea3517ab7864ca..."

    "FOUND mv=fe8f9ffd8a8de9674263932e903a2e56
Hash: 000000015a8c09f5..."

    "✅ Found solution!
Mutation vector: 0b99c44ec58929a7fa7e654369d1d995
Hash: 000000015a966ce0..."
)

echo "Testing different output formats:"
echo "================================="

for i in "${!TEST_OUTPUTS[@]}"; do
    echo ""
    echo "Test $((i+1)):"
    echo "Input:"
    echo "${TEST_OUTPUTS[$i]}"
    echo ""
    
    MINER_OUTPUT="${TEST_OUTPUTS[$i]}"
    
    # Try different extraction patterns
    if echo "$MINER_OUTPUT" | grep -q "mv="; then
        # Format: "FOUND mv=abcd1234..."
        MUTATION_VECTOR=$(echo "$MINER_OUTPUT" | grep "FOUND" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
        echo "Pattern: mv= format"
    elif echo "$MINER_OUTPUT" | grep -q "Mutation vector:"; then
        # Format: "Mutation vector: abcd1234"
        MUTATION_VECTOR=$(echo "$MINER_OUTPUT" | grep "Mutation vector:" | sed 's/.*Mutation vector: *\([a-f0-9]*\).*/\1/')
        echo "Pattern: Mutation vector: format"
    else
        # Try to find any hex pattern after FOUND or SOLUTION
        MUTATION_VECTOR=$(echo "$MINER_OUTPUT" | grep -E "(FOUND|SOLUTION)" -A 5 | grep -oE '[a-f0-9]{16,}' | head -1)
        echo "Pattern: hex search after FOUND/SOLUTION"
    fi
    
    # Extract hash
    SOLUTION_HASH=$(echo "$MINER_OUTPUT" | grep "Hash:" | sed 's/.*Hash: *//' | sed 's/[^a-f0-9].*//' || echo "N/A")
    
    echo "Extracted:"
    echo "  Mutation vector: '$MUTATION_VECTOR'"
    echo "  Hash: '$SOLUTION_HASH'"
    
    # Validate
    if [ -z "$MUTATION_VECTOR" ] || ! echo "$MUTATION_VECTOR" | grep -qE '^[a-f0-9]+$'; then
        echo "  ❌ Invalid mutation vector!"
    else
        echo "  ✅ Valid mutation vector"
    fi
done

echo ""
echo "🧪 To debug your actual miner output:"
echo "  export DEBUG_SOLUTION=true"
echo "  ./mine-gpu.sh"
