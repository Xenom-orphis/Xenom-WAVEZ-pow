# Miner Address Reward Fix

## Problem

Mining rewards were going to the node's wallet address (block signer) instead of the external miner's address, even when `--miner-address` was specified.

## Root Cause

The Waves blockchain requires blocks to be **signed** by an account with a private key (the node's wallet). The miner address was only used in the template but not stored in the block, so rewards defaulted to the block signer's address.

## Solution

### 1. Store Miner Address in Block

**Modified:** `node/src/main/scala/com/wavesplatform/api/http/PowBlockPersister.scala`

- Added `minerAddress: Option[String]` parameter to `persistPowBlock()`
- Encode miner address in block's `featureVotes` field (PoW blocks don't use feature votes)
- Format: Convert address bytes to sequence of shorts (2 bytes per short)

```scala
val featureVotes: Seq[Short] = minerAddress match {
  case Some(addr) =>
    val addressBytes = Address.fromString(addr).explicitGet().bytes
    addressBytes.grouped(2).map { pair =>
      val high = (pair(0) & 0xFF) << 8
      val low = if (pair.length > 1) (pair(1) & 0xFF) else 0
      (high | low).toShort
    }.toSeq
  case None => Seq.empty
}
```

### 2. Pass Miner Address in Submission

**Modified:** `node/src/main/scala/com/wavesplatform/api/http/BlockHeaderRoutes.scala`

- Added `miner_address: Option[String]` to `MiningSubmission` case class
- Pass miner address to `persistPowBlock()` when submitting solution

**Modified:** `xenom-miner-rust/src/node_client.rs`

- Added `miner_address: Option<String>` to `MiningSubmission` struct
- Include miner address from `NodeClient` in submission

### 3. Extract and Use Miner Address for Rewards

**Modified:** `node/src/main/scala/com/wavesplatform/state/diffs/BlockDiffer.scala`

- Added `extractMinerAddress()` helper function to decode address from feature votes
- Use extracted miner address for rewards instead of `block.sender.toAddress`

```scala
def extractMinerAddress(block: Block): Option[Address] = {
  if (block.header.rewardVote == -1L && block.header.featureVotes.nonEmpty) {
    val addressBytes = block.header.featureVotes.flatMap { short =>
      val high = ((short >> 8) & 0xFF).toByte
      val low = (short & 0xFF).toByte
      Seq(high, low)
    }.toArray
    Some(Address.fromBytes(addressBytes).explicitGet())
  } else {
    None
  }
}

// Use miner address for rewards
minerAddress = extractMinerAddress(block).getOrElse(block.sender.toAddress)
totalMinerPortfolio = Map(minerAddress -> totalMinerReward)
```

## Files Changed

### Node (Scala)
1. `node/src/main/scala/com/wavesplatform/api/http/PowBlockPersister.scala`
2. `node/src/main/scala/com/wavesplatform/api/http/BlockHeaderRoutes.scala`
3. `node/src/main/scala/com/wavesplatform/state/diffs/BlockDiffer.scala`

### Miner (Rust)
1. `xenom-miner-rust/src/node_client.rs`

## How It Works

1. **Template Creation**: Node creates template with miner address in response
2. **Mining**: Miner solves PoW and submits solution with miner address
3. **Block Creation**: Node encodes miner address in block's feature votes
4. **Reward Distribution**: BlockDiffer extracts miner address and credits rewards to it

## Testing

```bash
# Rebuild node
cd node
sbt assembly

# Rebuild miner
cd ../xenom-miner-rust
cargo build --release --features cuda

# Mine with external address
./target/release/xenom-miner-rust \
  --mine-loop \
  --node-url http://localhost:36669 \
  --miner-address 3MEUNP631SEHXuEskkGJKSsEc1wfdMBaq4N \
  --gpu \
  --gpu-brute

# Check balance
curl -X 'GET' \
  'http://localhost:36669/addresses/balance/3MEUNP631SEHXuEskkGJKSsEc1wfdMBaq4N' \
  -H 'accept: application/json'
```

## Backward Compatibility

- ✅ Blocks without miner address (empty feature votes) default to block signer
- ✅ Existing PoS blocks unaffected (rewardVote != -1)
- ✅ Node wallet mining still works (no miner address = use signer)

## Verification

After mining a block, check the logs:

```
🔨 Constructed PoW block for persistence:
   Height: 7442
   Block Signer: 3M1FxaiZ3jHC8QLZcE76QUgqfe4Krqu9CEv
   Miner Address (rewards): 3MEUNP631SEHXuEskkGJKSsEc1wfdMBaq4N
   💰 Mining Reward: 3.00000000 WAVES
```

Rewards should go to the **Miner Address**, not the Block Signer.
