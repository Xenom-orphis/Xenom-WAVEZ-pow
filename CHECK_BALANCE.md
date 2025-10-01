# Mining Rewards & Balance Tracking

## Mining Rewards System

✅ **Implemented!** Each mined block now includes:

- **Block Reward**: 100 WAVES per block
- **Coinbase Transaction**: Automatically created for miner
- **Balance Tracking**: BlockchainUpdater automatically updates miner's balance

## How It Works

```
Miner finds PoW solution
         ↓
Submit to node
         ↓
Node creates coinbase transaction:
  - Type: GenesisTransaction (special)
  - Recipient: Miner's address
  - Amount: 100 WAVES (10,000,000,000 wavelets)
         ↓
Block added to blockchain
         ↓
Miner's balance increases by 100 WAVES! 💰
```

## Check Your Mining Rewards

### 1. Get Your Wallet Address

From your config file:
```bash
grep "seed" node/waves-pow.conf
```

Or derive from seed:
```bash
# The wallet address in the config is:
# 3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF
```

### 2. Check Balance via REST API

```bash
# Check current balance
curl http://127.0.0.1:36669/addresses/balance/3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF

# Expected output:
{
  "address": "3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF",
  "confirmations": 0,
  "balance": 10000000000000  # In wavelets (100,000 WAVES if mined 1000 blocks)
}
```

### 3. Check Balance Details

```bash
# Get detailed balance info
curl http://127.0.0.1:36669/addresses/balance/details/3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF

# Expected output:
{
  "address": "3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF",
  "regular": 10000000000000,
  "generating": 10000000000000,
  "available": 10000000000000,
  "effective": 10000000000000
}
```

### 4. Watch Balance Increase in Real-Time

```bash
# Monitor balance every 5 seconds
watch -n 5 'curl -s http://127.0.0.1:36669/addresses/balance/3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF | jq'
```

### 5. Calculate Mining Earnings

```bash
# Get current blockchain height
HEIGHT=$(curl -s http://127.0.0.1:36669/blocks/height | jq .height)

# Calculate expected earnings (100 WAVES per block)
# Assuming you mined from block 1
EXPECTED_WAVES=$((HEIGHT * 100))
echo "Expected earnings: $EXPECTED_WAVES WAVES"

# Check actual balance
ACTUAL_WAVELETS=$(curl -s http://127.0.0.1:36669/addresses/balance/3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF | jq .balance)
ACTUAL_WAVES=$((ACTUAL_WAVELETS / 100000000))
echo "Actual balance: $ACTUAL_WAVES WAVES"
```

## Node Logs

When mining, you'll see:

```
INFO  ✅ Valid PoW solution found for block 842!
INFO     Mutation Vector: a1b2c3d4...
INFO  🔨 Constructed PoW block for persistence:
INFO     Height: 842
INFO     Generator Address: 3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF
INFO     💰 Mining Reward: 100 WAVES (10000000000 wavelets)
INFO  ✅ PoW block successfully added to blockchain at height 842
```

## Mining Statistics

```bash
# Get total blocks mined
curl http://127.0.0.1:36669/blocks/height

# Get last mined block info
curl http://127.0.0.1:36669/blocks/last | jq

# Check if you're the generator
curl http://127.0.0.1:36669/blocks/last | jq .generator
# Should match your wallet address
```

## Conversion

- **1 WAVES** = 100,000,000 wavelets (8 decimals)
- **100 WAVES** = 10,000,000,000 wavelets (block reward)

Example:
```
Balance: 150,000,000,000 wavelets
       = 150,000,000,000 / 100,000,000
       = 1,500 WAVES
       = 15 blocks mined
```

## Summary

✅ **Mining Rewards**: 100 WAVES per block  
✅ **Balance Tracking**: Automatic via BlockchainUpdater  
✅ **Check Balance**: REST API endpoints available  
✅ **Real-time Updates**: Balance increases with each block  

Mine away and watch your balance grow! 💰🚀
