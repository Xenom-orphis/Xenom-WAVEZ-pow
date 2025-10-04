# Mining to Your Own Wallet Address

Your blockchain now supports **mining to any wallet address** without configuring the node! This works like Bitcoin mining pools - just pass your address when requesting the mining template.

## Quick Start

### Option 1: Use Miner Address Flag (Recommended)

```bash
# Mine to your own address
./xenom-miner-rust/target/release/xenom-miner-rust \
  --mine-loop \
  --gpu \
  --gpu-brute \
  --node-url "http://localhost:36669" \
  --miner-address "3MyWalletAddressHere123456789xyz" \
  --population 32768 \
  --batches 50000
```

Or with the shell script:

```bash
export MINER_ADDRESS="3MyWalletAddressHere123456789xyz"
./mine-loop.sh
```

### Option 2: Request Template with Address via API

```bash
# Get mining template for your address
curl "http://localhost:36669/mining/template?address=3MyWalletAddressHere123456789xyz"

# Response includes your address:
{
  "height": 25,
  "header_prefix_hex": "...",
  "difficulty_bits": "1f00ffff",
  "target_hex": "...",
  "timestamp": 1234567890123,
  "miner_address": "3MyWalletAddressHere123456789xyz"
}
```

## Generate a New Wallet Address

### Method 1: Via REST API

```bash
# Generate new seed phrase
curl -s "http://localhost:36669/addresses/seed" \
  -H "X-API-Key: ridethewaves!" | jq .

# Output:
# {
#   "seed": "word1 word2 word3 ... word15"
# }

# Get address from seed
curl -s -X POST "http://localhost:36669/addresses" \
  -H "X-API-Key: ridethewaves!" \
  -H "Content-Type: application/json" \
  -d '{"seed": "your seed phrase here"}' | jq .

# Output:
# {
#   "address": "3Mxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# }
```

### Method 2: Use Waves Wallet

1. Download Waves Keeper or Waves Exchange wallet
2. Create new account
3. Copy your address (starts with `3M` for testnet)
4. Use it for mining

## How It Works

### Architecture

1. **Miner requests template** with optional address parameter:
   ```
   GET /mining/template?address=3MyAddress...
   ```

2. **Node creates template** with that address as reward recipient

3. **Miner finds solution** and submits

4. **Rewards go to your address** when block is accepted

### Fallback Behavior

If no address is provided:
1. Uses node's configured wallet address (from `waves-pow.conf`)
2. If no wallet configured, uses genesis address
3. Logs a warning if using fallback

## Complete Example

```bash
#!/bin/bash
# generate-wallet-and-mine.sh

NODE_URL="http://localhost:36669"
API_KEY="ridethewaves!"

# 1. Generate new wallet
echo "🔑 Generating new wallet..."
SEED=$(curl -s "$NODE_URL/addresses/seed" -H "X-API-Key: $API_KEY" | jq -r .seed)
echo "   Seed: $SEED"
echo "   ⚠️  SAVE THIS SEED PHRASE SECURELY!"

# 2. Get address
ADDRESS=$(curl -s -X POST "$NODE_URL/addresses" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"seed\": \"$SEED\"}" | jq -r .address)
echo "   Address: $ADDRESS"

# 3. Start mining to this address
echo ""
echo "💰 Mining rewards will go to: $ADDRESS"
echo "🚀 Starting miner..."

./xenom-miner-rust/target/release/xenom-miner-rust \
  --mine-loop \
  --gpu \
  --gpu-brute \
  --node-url "$NODE_URL" \
  --miner-address "$ADDRESS" \
  --population 32768 \
  --batches 50000
```

## Check Your Balance

```bash
# Check wallet balance
ADDRESS="3MyWalletAddressHere"
curl -s "http://localhost:36669/addresses/balance/details/$ADDRESS" | jq .

# Output:
# {
#   "address": "3MyWalletAddressHere",
#   "regular": 600000000,         # 6 WAVES (1 WAVES = 100,000,000 waveslets)
#   "generating": 600000000,
#   "available": 600000000,
#   "effective": 600000000
# }
```

## Mining Pool Support

This architecture supports mining pools:

### Pool Operator
```bash
# Pool provides template with pool's address
curl "http://node-url/mining/template?address=3PoolWalletAddress"
```

### Pool Miner
```bash
# Miner works on pool's template
./xenom-miner-rust --mine-loop \
  --node-url "http://pool-url" \
  --miner-address "3PoolWalletAddress"
```

Pool distributes rewards to miners based on shares submitted.

## Security Notes

1. **Keep your seed phrase safe** - It's the only way to access your funds
2. **Validate addresses** - Always double-check the address format (should start with `3M`)
3. **Test with small amounts first** - Mine a few blocks to verify everything works
4. **Backup your seed** - Write it down or use a hardware wallet

## Troubleshooting

### "No wallet configured" warning
- The node has no wallet in config
- Either provide `--miner-address` or configure node wallet
- Mining still works, just uses default address

### Invalid address format
- Addresses must be valid Waves addresses
- Testnet: starts with `3M`
- Mainnet: starts with `3P`

### Rewards not showing
- Check block explorer to verify blocks are mined
- Wait for block confirmation (usually instant)
- Verify correct address was used: check node logs

## Integration with mine-loop.sh

Update `mine-loop.sh` to support miner address:

```bash
#!/bin/bash
NODE_URL="${NODE_URL:-http://localhost:36669}"
MINER_ADDRESS="${MINER_ADDRESS:-}"  # Set via environment variable
POPULATION="${POPULATION:-32768}"
BATCHES="${BATCHES:-50000}"

ARGS="--mine-loop --gpu --gpu-brute --node-url $NODE_URL --population $POPULATION --batches $BATCHES"

# Add miner address if provided
if [ ! -z "$MINER_ADDRESS" ]; then
    echo "💰 Mining to address: $MINER_ADDRESS"
    ARGS="$ARGS --miner-address $MINER_ADDRESS"
fi

exec ./xenom-miner-rust/target/release/xenom-miner-rust $ARGS
```

Usage:
```bash
# Mine to your address
MINER_ADDRESS="3MyAddress..." ./mine-loop.sh

# Or without address (uses node wallet)
./mine-loop.sh
```

---

**You can now mine to any wallet without touching the node configuration!** 🎉
