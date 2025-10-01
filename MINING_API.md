# Waves PoW Mining API

## Overview

The Waves PoW node now exposes HTTP endpoints for remote miners to fetch block headers and mine them using the custom PoW consensus algorithm with mutation vectors.

## API Endpoints

All endpoints are available at `http://<node-ip>:36669/block/<height>/...`

### 1. Get Block Header Prefix (for Mining)

**Endpoint**: `GET /block/<height>/headerHex`

Returns the block header **without** the mutation vector - this is what miners should use to find a valid mutation vector.

**Example Request**:
```bash
curl http://127.0.0.1:36669/block/0/headerHex
```

**Example Response**:
```json
{
  "header_prefix_hex": "0000000100000000000000000000000000000000000000000000000000000000000000009338d4a0e96efd5d942e7095b636ad93af87727603c869e2496d9dd0f98b40bb0000000066e63fa0000000001f00ffff000000000000000000000010"
}
```

**Use Case**: Pass this hex string to your miner to find a valid mutation vector that satisfies the PoW difficulty.

---

### 2. Get Block Header JSON

**Endpoint**: `GET /block/<height>/headerJson`

Returns the complete block header in human-readable JSON format.

**Example Request**:
```bash
curl http://127.0.0.1:36669/block/0/headerJson
```

**Example Response**:
```json
{
  "version": 1,
  "parentId": "0000000000000000000000000000000000000000000000000000000000000000",
  "stateRoot": "9338d4a0e96efd5d942e7095b636ad93af87727603c869e2496d9dd0f98b40bb",
  "timestamp": 1726365600,
  "difficultyBits": "1f00ffff",
  "nonce": 0,
  "mutationVector": "00000000000000000000000000000000"
}
```

**Use Case**: Inspect block header details, debug mining parameters, or verify block structure.

---

### 3. Get Full Block Header (with Mutation Vector)

**Endpoint**: `GET /block/<height>/headerRawHex`

Returns the complete serialized block header including the mutation vector.

**Example Request**:
```bash
curl http://127.0.0.1:36669/block/0/headerRawHex
```

**Example Response**:
```json
{
  "header_hex": "0000000100000000000000000000000000000000000000000000000000000000000000009338d4a0e96efd5d942e7095b636ad93af87727603c869e2496d9dd0f98b40bb0000000066e63fa0000000001f00ffff00000000000000000000001000000000000000000000000000000000"
}
```

**Use Case**: Verify complete block header after mining, validate block serialization, or broadcast mined blocks.

---

### 4. Submit Mined Block Solution

**Endpoint**: `POST /mining/submit`

Submits a mined mutation vector for validation. The node will reconstruct the complete block header with the provided mutation vector and validate the PoW solution.

**Request Body**:
```json
{
  "height": 0,
  "mutation_vector_hex": "4a2de176737db50adec3fbcdc8508640"
}
```

**Example Request**:
```bash
curl -X POST http://127.0.0.1:36669/mining/submit \
  -H "Content-Type: application/json" \
  -d '{
    "height": 0,
    "mutation_vector_hex": "4a2de176737db50adec3fbcdc8508640"
  }'
```

**Success Response** (200 OK):
```json
{
  "success": true,
  "message": "Valid PoW solution accepted",
  "hash": "0000000100000000000000000000000000000000000000000000000000000000000000009338d4a0e96efd5d942e7095b636ad93af87727603c869e2496d9dd0f98b40bb0000000066e63fa0000000001f00ffff00000000000000000000001000000000000000004a2de176737db50adec3fbcdc8508640"
}
```

**Failure Response - Invalid PoW** (200 OK):
```json
{
  "success": false,
  "message": "Invalid PoW: solution does not meet difficulty target"
}
```

**Failure Response - Invalid Format** (400 Bad Request):
```json
{
  "success": false,
  "message": "Invalid mutation vector hex format"
}
```

**Failure Response - Block Not Found** (404 Not Found):
```json
{
  "success": false,
  "message": "Block at height 123 not found"
}
```

**Use Case**: Submit and validate mining solutions, receive confirmation of valid PoW blocks.

---

## Block Header Format

The PoW consensus uses the following block header structure:

| Field | Type | Size | Description |
|-------|------|------|-------------|
| `version` | int32 (BE) | 4 bytes | Block version number |
| `parentId` | bytes | 32 bytes | Hash of previous block |
| `stateRoot` | bytes | 32 bytes | Merkle root of state |
| `timestamp` | int64 (BE) | 8 bytes | Unix timestamp in seconds |
| `difficultyBits` | int64 (BE) | 8 bytes | Compact difficulty target (0x1f00ffff) |
| `nonce` | int64 (BE) | 8 bytes | Mining nonce |
| `mutationVectorLength` | int32 (BE) | 4 bytes | Length of mutation vector (16 bytes) |
| `mutationVector` | bytes | N bytes | The variable part that miners optimize |

**Total header size**: 96 bytes (80 bytes prefix + 4 bytes length + 12 bytes padding = 96 for 16-byte MV)

**Mining target**: Miners search for a `mutationVector` such that `BLAKE3(header) < target`

---

## Mining Workflow

### Step 1: Fetch Current Block Header

```bash
# Get the latest block height from the node
HEIGHT=$(curl -s http://127.0.0.1:36669/node/height | jq -r .height)

# Fetch the block header prefix for mining
HEADER_HEX=$(curl -s http://127.0.0.1:36669/block/$HEIGHT/headerHex | jq -r .header_prefix_hex)
```

### Step 2: Mine with Rust Miner (Genetic Algorithm)

```bash
cd xenom-miner-rust

cargo run --release -- \
  --header-hex "$HEADER_HEX" \
  --bits-hex 1f00ffff \
  --mv-len 16 \
  --population 1024 \
  --generations 5000
```

**Expected Output**:
```
gen=0 best_f=0.15372006706752375 time=832.625µs
gen=10 best_f=0.15352896899175972 time=7.163083ms
gen=20 best_f=0.15343417373103452 time=12.774083ms
FOUND solution generation=23 idx=152 mv=4a2de176737db50adec3fbcdc8508640 time=14.060208ms
done
```

The miner will output the valid `mutationVector` (e.g., `4a2de176737db50adec3fbcdc8508640`).

### Step 3: Submit Mined Block

```bash
# Submit the found mutation vector to the node for validation
curl -X POST http://127.0.0.1:36669/mining/submit \
  -H "Content-Type: application/json" \
  -d '{
    "height": 0,
    "mutation_vector_hex": "4a2de176737db50adec3fbcdc8508640"
  }'
```

**Expected Response (Success)**:
```json
{
  "success": true,
  "message": "Valid PoW solution accepted",
  "hash": "0000000100000000..." 
}
```

**Expected Response (Failure)**:
```json
{
  "success": false,
  "message": "Invalid PoW: solution does not meet difficulty target"
}
```

---

## Mapping: Waves Blockchain → PoW Headers

The node automatically maps existing Waves blocks to the PoW header format:

| PoW Field | Waves Field | Mapping Logic |
|-----------|-------------|---------------|
| `version` | `header.version` | Direct cast (byte → int) |
| `parentId` | `header.reference` | Previous block ID (32 bytes) |
| `stateRoot` | `header.stateHash` or `header.transactionsRoot` | Use stateHash if available |
| `timestamp` | `header.timestamp` | Unix timestamp (milliseconds → seconds) |
| `difficultyBits` | Fixed | `0x1f00ffff` (for now) |
| `nonce` | `header.timestamp` | Waves doesn't have nonce, reuse timestamp |
| `mutationVector` | Empty | `[]` (Waves blocks don't have mutation vector) |

**Note**: Only blocks mined with PoW will have non-empty mutation vectors. Historical Waves blocks (PoS) will have empty mutation vectors.

---

## Configuration

The PoW difficulty and mutation vector size are configured in:

- **Genesis Block**: `node/src/main/scala/consensus/Genesis.scala`
  - Difficulty: `0x1f00ffff`
  - Mutation Vector Length: 16 bytes

- **Node Config**: `node/waves-pow.conf`
  - REST API Port: 36669
  - Mining enabled/disabled

---

## Performance Considerations

### Genetic Algorithm Miner (Rust)

- **Mutation Vector Size**: 16 bytes = 2^128 possible solutions
- **Search Space**: Massive - requires heuristic optimization
- **Expected Time**: ~10-50ms per solution (depends on hardware)
- **Population Size**: 1024 (configurable)
- **Generations**: 5000 max (usually finds solution much earlier)

### Difficulty Adjustment

Current difficulty: `0x1f00ffff` (Bitcoin-style compact format)
- Target hash: `0x00ffff * 2^208`
- Easier than Bitcoin's genesis block
- Adjustable via hard fork

---

## Security Notes

1. **Block Header Integrity**: All block headers are fetched from the local blockchain state
2. **Mutation Vector Validation**: Miners must find a valid MV that passes `BLAKE3(header) < target`
3. **No Authentication**: API endpoints are public (add auth if needed in production)
4. **Rate Limiting**: Consider adding rate limits for `/block/<height>/headerHex` in production

---

## Troubleshooting

### Issue: "Block not found at height X"

**Cause**: The requested block height doesn't exist yet.

**Solution**: Check current height with `curl http://127.0.0.1:36669/node/height`

### Issue: Miner can't find solution

**Cause**: Difficulty too high, or mutation vector too short.

**Solution**: 
- Increase mutation vector length (`--mv-len`)
- Increase population size (`--population`)
- Increase max generations (`--generations`)

### Issue: Connection refused

**Cause**: Node not running or REST API disabled.

**Solution**: 
- Start node: `java -jar node/target/waves-all-*.jar node/waves-pow.conf`
- Check `waves.rest-api.enable = yes` in config

---

## Development Roadmap

- [ ] Add block submission endpoint (`POST /mining/submit`)
- [ ] Implement dynamic difficulty adjustment based on block time
- [ ] Add WebSocket endpoint for real-time block updates
- [ ] Support pooled mining (stratum protocol)
- [ ] Add mining statistics and metrics endpoint

---

## Example: Complete Mining Script

```bash
#!/bin/bash

NODE_URL="http://127.0.0.1:36669"
MINER_DIR="xenom-miner-rust"

while true; do
    echo "Fetching latest block..."
    HEADER=$(curl -s "$NODE_URL/block/0/headerHex" | jq -r .header_prefix_hex)
    
    echo "Mining block with header: $HEADER"
    cd "$MINER_DIR"
    RESULT=$(cargo run --release -- \
        --header-hex "$HEADER" \
        --bits-hex 1f00ffff \
        --mv-len 16 \
        --population 1024 \
        --generations 5000 2>&1)
    
    if echo "$RESULT" | grep -q "FOUND solution"; then
        MV=$(echo "$RESULT" | grep "FOUND solution" | sed 's/.*mv=\([a-f0-9]*\).*/\1/')
        echo "✅ Found solution: $MV"
        # TODO: Submit block with mutation vector
    else
        echo "❌ No solution found, retrying..."
    fi
    
    sleep 1
done
```

Save as `mine.sh` and run with `chmod +x mine.sh && ./mine.sh`

---

## Contact & Support

For issues or questions:
- GitHub Issues: [Waves_Pow Repository]
- Documentation: See `README.md`
- Example Code: See `xenom-miner-rust/` directory
