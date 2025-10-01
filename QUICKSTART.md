# Waves PoW Mining Quickstart

## Prerequisites

- Java 11+ (for running the node)
- Rust & Cargo (for the miner)
- `jq` (for JSON parsing)
- `curl` (for API calls)

## 1. Build Everything

```bash
# Build the node
sbt buildPlatformIndependentArtifacts

# Build the miner
cd xenom-miner-rust
cargo build --release
cd ..

# Make mining script executable
chmod +x mine.sh
```

## 2. Start the Node

```bash
java -jar node/target/waves-all-*.jar node/waves-pow.conf
```

Wait for the node to start. You should see:
```
REST API was bound on 0.0.0.0:36669
```

## 3. Test the API (Optional)

In a new terminal:

```bash
# Get genesis block header
curl http://127.0.0.1:36669/block/0/headerHex | jq

# Get block info as JSON
curl http://127.0.0.1:36669/block/0/headerJson | jq
```

## 4. Start Mining

### Option A: Automated Mining Script

```bash
./mine.sh
```

This will continuously:
1. Fetch the latest block header
2. Mine it with the genetic algorithm
3. Submit valid solutions to the node
4. Repeat

**Expected Output**:
```
----------------------------------------
Fetching latest block...
Mining block 0 with header prefix: 00000001000000000000000000000000...
✅ Found solution: 4a2de176737db50adec3fbcdc8508640
📤 Submitting solution to node...
✅ Solution accepted!
   Message: Valid PoW solution accepted
   Block hash: 0000000100000000...
```

### Option B: Manual Mining

```bash
# 1. Get block header
HEADER=$(curl -s http://127.0.0.1:36669/block/0/headerHex | jq -r .header_prefix_hex)

# 2. Mine it
cd xenom-miner-rust
cargo run --release -- \
  --header-hex "$HEADER" \
  --bits-hex 1f00ffff \
  --mv-len 16 \
  --population 1024 \
  --generations 5000

# 3. Extract mutation vector from output
# Look for: FOUND solution generation=X idx=Y mv=ABCDEF... time=Zms

# 4. Submit solution
curl -X POST http://127.0.0.1:36669/mining/submit \
  -H "Content-Type: application/json" \
  -d '{
    "height": 0,
    "mutation_vector_hex": "YOUR_MV_HERE"
  }' | jq
```

## API Endpoints Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/block/<height>/headerHex` | Get block header prefix for mining |
| GET | `/block/<height>/headerJson` | Get block header as JSON |
| GET | `/block/<height>/headerRawHex` | Get full block header with MV |
| POST | `/mining/submit` | Submit mined mutation vector |

## Mining Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--header-hex` | (required) | Block header prefix in hex |
| `--bits-hex` | `1f00ffff` | Difficulty target (compact format) |
| `--mv-len` | `16` | Mutation vector length in bytes |
| `--population` | `1024` | GA population size |
| `--generations` | `5000` | Max generations to evolve |

## Tuning Performance

### For Faster Mining (Lower Quality Solutions)
```bash
--population 512 --generations 1000
```

### For Better Solutions (Slower)
```bash
--population 2048 --generations 10000
```

### For Very Fast Testing
```bash
--population 256 --generations 500
```

## Troubleshooting

### "Connection refused"
- **Problem**: Node is not running
- **Solution**: Start the node with `java -jar node/target/waves-all-*.jar node/waves-pow.conf`

### "Failed to fetch block header"
- **Problem**: Node is starting up or REST API is disabled
- **Solution**: Wait 10 seconds after starting the node, or check `waves.rest-api.enable = yes` in config

### "Invalid PoW: solution does not meet difficulty target"
- **Problem**: The mutation vector doesn't satisfy PoW
- **Solution**: This shouldn't happen with the genetic algorithm. Check that `--bits-hex` matches the block's difficulty

### Miner finds no solution
- **Problem**: Max generations reached without finding valid solution
- **Solution**: Increase `--generations` or `--population` size

### "Building miner..."  keeps appearing
- **Problem**: Miner binary not in expected location
- **Solution**: Build manually: `cd xenom-miner-rust && cargo build --release && cd ..`

## Configuration Files

### Node Config: `node/waves-pow.conf`

```hocon
waves {
  rest-api {
    enable = yes
    bind-address = "0.0.0.0"
    port = 36669
    api-key-hash = "..."
  }
  
  miner {
    enable = yes
    quorum = 1
  }
}
```

### Mining Script: `mine.sh`

```bash
NODE_URL="http://127.0.0.1:36669"   # Change for remote node
HEIGHT=0                             # Change to mine specific block
```

## Next Steps

1. **Monitor Mining**: Watch the console output for accepted solutions
2. **Check Block Hashes**: Verify PoW solutions meet the difficulty target
3. **Experiment with Parameters**: Tune GA parameters for your hardware
4. **Implement Block Storage**: Store validated blocks in the blockchain
5. **Network Integration**: Broadcast mined blocks to peers

## Performance Benchmarks

| Hardware | Population | Generations | Avg Time per Solution |
|----------|------------|-------------|----------------------|
| M1 Mac | 1024 | 5000 | ~15-30ms |
| Intel i7 | 1024 | 5000 | ~25-50ms |
| AMD Ryzen | 1024 | 5000 | ~20-40ms |

*Note: Times vary based on difficulty and random initialization*

## Support

- **Documentation**: See `MINING_API.md` for complete API reference
- **Issues**: Check GitHub Issues for known problems
- **Example Code**: See `mine.sh` and `xenom-miner-rust/` for reference implementations
