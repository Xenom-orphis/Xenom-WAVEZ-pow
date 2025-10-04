#!/bin/bash
# Generate a new Waves wallet address for mining

NODE_URL="${NODE_URL:-http://localhost:36669}"
API_KEY="node-integration-tests"

echo "🔑 Generating new wallet..."
echo "   Node: $NODE_URL"
echo ""

# Test node connectivity
echo "Testing node connectivity..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$NODE_URL/wallet/seed" -H "X-API-Key: $API_KEY")

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Cannot connect to node at $NODE_URL"
    echo "   HTTP Status: $HTTP_CODE"
    echo ""
    echo "💡 To start the node:"
    echo "   cd /workspace/Xenom-WAVEZ-pow"
    echo "   java --add-opens java.base/sun.nio.ch=ALL-UNNAMED \\"
    echo "        -jar node/target/scala-2.13/waves-all-*.jar \\"
    echo "        node/waves-pow.conf &"
    exit 1
fi

# Generate seed phrase
RESPONSE=$(curl -s "$NODE_URL/wallet/seed" -H "X-API-Key: $API_KEY")
SEED=$(echo "$RESPONSE" | jq -r .seed 2>/dev/null)

if [ -z "$SEED" ] || [ "$SEED" = "null" ]; then
    echo "❌ Failed to generate seed"
    echo "   Response: $RESPONSE"
    exit 1
fi

# Generate new address (this creates a new account in the wallet)
ADDRESS=$(curl -s -X POST "$NODE_URL/addresses" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" | jq -r .address)

if [ -z "$ADDRESS" ] || [ "$ADDRESS" = "null" ]; then
    echo "❌ Failed to generate address"
    exit 1
fi

# Display results
echo "✅ Wallet created successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 WALLET INFORMATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💰 Address: $ADDRESS"
echo ""
echo "🔐 Seed Phrase:"
echo "   $SEED"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  IMPORTANT: Save your seed phrase securely!"
echo "   This is the ONLY way to recover your wallet."
echo ""
echo "📝 Save to file:"
echo "   echo '$SEED' > my-wallet-seed.txt"
echo ""
echo "⛏️  Start mining to this address:"
echo "   MINER_ADDRESS=$ADDRESS ./mine-loop.sh"
echo ""
echo "💵 Check balance:"
echo "   curl -s \"$NODE_URL/addresses/balance/details/$ADDRESS\" | jq ."
echo ""
