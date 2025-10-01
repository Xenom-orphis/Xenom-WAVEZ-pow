# Blockchain Integration: Persisting PoW Blocks

## Current Status

✅ **What Works**:
- Miners can fetch block headers from the API
- Genetic algorithm finds valid mutation vectors
- API validates PoW solutions (BLAKE3 hash < target)
- Valid solutions are accepted and logged

❌ **What's Missing**:
- **Validated blocks are NOT added to the blockchain**
- The blockchain continues with PoS consensus (appender continues adding PoS blocks)
- Miners keep re-mining the same block because it never advances

## Why Blocks Aren't Being Added

The current `/mining/submit` endpoint only **validates** the PoW but doesn't:

1. **Construct a full Waves `Block`** object (needs transactions, signature, etc.)
2. **Call `BlockAppender`** to add the block to the blockchain
3. **Broadcast** the block to network peers
4. **Update** the blockchain state

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    Current Implementation                      │
├──────────────────────────────────────────────────────────────┤
│                                                                │
│  Miner → GET /block/N/headerHex                               │
│       ↓                                                        │
│  Find valid mutation vector                                   │
│       ↓                                                        │
│  POST /mining/submit                                          │
│       ↓                                                        │
│  ✅ Validate PoW (BLAKE3 hash check)                          │
│       ↓                                                        │
│  ⚠️  Log success (but DON'T add to blockchain)               │
│                                                                │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                    What Needs to Happen                        │
├──────────────────────────────────────────────────────────────┤
│                                                                │
│  Miner → GET /block/N/headerHex                               │
│       ↓                                                        │
│  Find valid mutation vector                                   │
│       ↓                                                        │
│  POST /mining/submit                                          │
│       ↓                                                        │
│  ✅ Validate PoW                                              │
│       ↓                                                        │
│  ✅ Construct full Block object                               │
│       ↓                                                        │
│  ✅ Call BlockAppender.apply(block)                           │
│       ↓                                                        │
│  ✅ Broadcast to network                                      │
│       ↓                                                        │
│  ✅ Blockchain height increases                               │
│                                                                │
└──────────────────────────────────────────────────────────────┘
```

## What Needs to Be Implemented

### 1. Block Construction

Currently, we only have a `consensus.BlockHeader` (PoW format). We need to construct a full Waves `Block`:

```scala
case class Block(
  header: BlockHeader,           // Waves BlockHeader (not consensus.BlockHeader)
  signature: ByteStr,            // Block signature
  transactionData: Seq[Transaction]  // Transactions in this block
)
```

**Challenges**:
- Map `consensus.BlockHeader` → Waves `BlockHeader`
- Generate block signature (requires private key)
- Include transactions (or create empty block)
- Handle `baseTarget`, `generationSignature`, etc. for PoS compatibility

### 2. BlockAppender Integration

The `BlockAppender` is responsible for:
- Validating the complete block
- Updating blockchain state
- Persisting to database
- Broadcasting to peers

**Location**: `com.wavesplatform.mining.BlockAppender`

**Current Usage** (in `Application.scala`):
```scala
val processBlock = BlockAppender(
  blockchainUpdater,
  time,
  utxStorage,
  pos,
  allChannels,
  peerDatabase,
  blockChallenger,
  appenderScheduler
)
```

**What We Need**:
```scala
// In BlockHeaderRoutes, after validating PoW:
if (minedHeader.validatePow()) {
  // 1. Construct full Waves Block
  val wavesBlock = constructWavesBlock(minedHeader, mvBytes)
  
  // 2. Append to blockchain
  blockAppender(wavesBlock, None) match {
    case Right(_) =>
      log.info(s"✅ Block added to blockchain at height ${blockchainUpdater.height}")
      MiningSubmissionResponse(success = true, message = "Block added to blockchain", ...)
    case Left(error) =>
      log.error(s"❌ Failed to append block: $error")
      MiningSubmissionResponse(success = false, message = s"Block validation failed: $error", ...)
  }
}
```

### 3. Block Signature Generation

Waves blocks require a valid signature. Options:

**Option A: Use Miner's Wallet**
```scala
// Get generator account from wallet
val generator = wallet.privateKeyAccounts.headOption.getOrElse(
  throw new RuntimeException("No accounts in wallet")
)

// Sign the block
val signature = crypto.sign(generator.privateKey, blockBytes)
```

**Option B: Accept Signature from Miner**
```scala
case class MiningSubmission(
  height: Long,
  mutation_vector_hex: String,
  signature_hex: String  // Miner provides signature
)
```

**Option C: Use Special PoW Generator** (Recommended)
```scala
// Create a dedicated PoW miner account
val powGenerator = KeyPair(/* dedicated key for PoW blocks */)
```

### 4. Transaction Handling

Waves blocks contain transactions. Options:

**Option A: Empty Blocks**
```scala
val block = Block(
  header = wavesHeader,
  signature = signature,
  transactionData = Seq.empty  // No transactions
)
```

**Option B: Include Pending Transactions**
```scala
// Get transactions from UTX pool
val txs = utxStorage.priorityPool
  .take(settings.minerSettings.maxTransactionsInBlock)
  .toSeq

val block = Block(
  header = wavesHeader,
  signature = signature,
  transactionData = txs
)
```

**Option C: Special PoW Reward Transaction**
```scala
// Create a coinbase transaction rewarding the miner
val coinbaseTx = /* ... */
val block = Block(
  header = wavesHeader,
  signature = signature,
  transactionData = Seq(coinbaseTx)
)
```

## Implementation Roadmap

### Phase 1: Basic Block Persistence (Minimal)

```scala
class BlockHeaderRoutes(
  blockStorage: BlockStorage,
  blockAppender: Block => Either[ValidationError, Unit],  // NEW
  wallet: Wallet                                          // NEW
) extends ApiRoute {
  
  // In submission handler:
  if (minedHeader.validatePow()) {
    // Construct minimal Waves block
    val wavesHeader = BlockHeader(
      version = minedHeader.version.toByte,
      timestamp = minedHeader.timestamp,
      reference = ByteStr(minedHeader.parentId),
      baseTarget = difficultyToBaseTarget(minedHeader.difficultyBits),
      generationSignature = ByteStr.empty,
      generator = wallet.privateKeyAccounts.head.publicKey,
      featureVotes = Seq.empty,
      rewardVote = -1L,
      transactionsRoot = ByteStr(minedHeader.stateRoot),
      stateHash = Some(ByteStr(minedHeader.stateRoot)),
      challengedHeader = None
    )
    
    val blockBytes = /* serialize header */
    val signature = crypto.sign(wallet.privateKeyAccounts.head, blockBytes)
    
    val block = Block(
      header = wavesHeader,
      signature = signature,
      transactionData = Seq.empty
    )
    
    // Append to blockchain
    blockAppender(block) match {
      case Right(_) => /* success */
      case Left(err) => /* failure */
    }
  }
}
```

### Phase 2: Full Integration

1. **Add PoW validation to block appender**
2. **Integrate with network layer** (broadcast PoW blocks)
3. **Difficulty adjustment** based on block time
4. **Fork resolution** (PoW vs PoS chains)
5. **Mining rewards** (coinbase transactions)

### Phase 3: Production Ready

1. **Mining pools** (stratum protocol)
2. **Distributed mining** (work distribution)
3. **Block templates** (updated transaction sets)
4. **Checkpoint system** (prevent deep reorgs)
5. **Hybrid consensus** (PoW + PoS)

## Quick Fix: Manual Block Persistence

For testing purposes, you can manually persist blocks:

```bash
# 1. Mine a block
./mine.sh

# 2. Extract the valid mutation vector from logs
# Node logs will show: "✅ Valid PoW solution found for block N!"

# 3. Manually construct and inject block (TODO: create admin endpoint)
curl -X POST http://127.0.0.1:36669/admin/injectPowBlock \
  -H "X-Api-Key: your-api-key" \
  -d '{
    "height": 540,
    "mutation_vector": "4a2de176737db50adec3fbcdc8508640",
    "transactions": []
  }'
```

## Why the Blockchain Keeps Advancing

The Waves node has a **miner** component that continuously:

1. Waits for the next block time slot (PoS)
2. Checks if this node is eligible to generate (based on stake)
3. Creates a new block with pending transactions
4. Adds it to the blockchain

**This is separate from our PoW mining!**

To stop PoS mining:

```hocon
# In waves-pow.conf
waves {
  miner {
    enable = no  # Disable PoS mining
  }
}
```

## Current Workaround

Since blocks aren't being persisted yet:

1. **Mine block 0** (genesis) repeatedly to test the genetic algorithm
2. **Validate PoW solutions** to ensure the system works
3. **Monitor node logs** to see valid solutions being found
4. **Prepare for integration** once block persistence is implemented

## Expected Behavior After Integration

```
----------------------------------------
Fetching current blockchain height...
Current blockchain height: 540
Fetching block 540 for mining template...
Mining block 540 with header prefix: 00000001000000000000000000000000...
✅ Found solution: 4a2de176737db50adec3fbcdc8508640
📤 Submitting solution to node...
✅ Solution accepted!
   Message: Block added to blockchain
   Block hash: 0000000100000000...
   New blockchain height: 541

----------------------------------------
Fetching current blockchain height...
Current blockchain height: 541  <-- HEIGHT INCREASED!
Fetching block 541 for mining template...
Mining block 541 with header prefix: 00000001abc123...  <-- NEW BLOCK!
...
```

## Next Steps

1. ✅ Update mining script to fetch current height
2. ✅ Add logging for valid PoW solutions
3. ⏳ Implement block construction in `/mining/submit`
4. ⏳ Wire up `BlockAppender` to persist blocks
5. ⏳ Test full mining → persistence → blockchain advancement cycle
6. ⏳ Add network broadcast for PoW blocks

## References

- **Block Structure**: `node/src/main/scala/com/wavesplatform/block/Block.scala`
- **BlockAppender**: `node/src/main/scala/com/wavesplatform/mining/BlockAppender.scala`
- **Blockchain Updater**: `node/src/main/scala/com/wavesplatform/state/BlockchainUpdaterImpl.scala`
- **PoW Validation**: `node/src/main/scala/consensus/BlockHeader.scala`

## Support

For questions about blockchain integration:
- Check `Application.scala` for how `BlockAppender` is wired up
- See `Miner.scala` for how PoS blocks are generated
- Review `BlockchainUpdaterImpl.scala` for state management
