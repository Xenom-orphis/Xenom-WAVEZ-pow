# PoW Validation Failure: Root Cause & Solution

## Problem

All mining submissions are being rejected with:
```
❌ Solution rejected: Invalid PoW: solution does not meet difficulty target
```

Even though the genetic algorithm is finding "solutions", they're not valid.

## Root Cause

**You're mining EXISTING Waves PoS blocks instead of creating NEW PoW block templates.**

### What's Happening

1. Miner fetches block 626 (existing Waves PoS block)
2. Block 626 has header: `version: 5, timestamp: X, reference: Y, ...` (Waves PoS format)
3. Genetic algorithm finds mutation vector for this header
4. Submission reconstructs header with MV and validates PoW
5. **PoW validation FAILS** because:
   - Waves PoS header format ≠ PoW consensus header format
   - Different serialization, different fields, wrong version

### Header Format Mismatch

**Waves PoS Block** (what you're mining):
```
version: 5 (byte)
timestamp: 8 bytes
reference: 32 bytes  
baseTarget: 8 bytes
generationSignature: 32 bytes
generator: 32 bytes (PublicKey)
... (many more fields)
```

**PoW Consensus Block** (what you SHOULD be mining):
```
version: 1 (int, 4 bytes)
parentId: 32 bytes
stateRoot: 32 bytes
timestamp: 8 bytes (long)
difficultyBits: 8 bytes (long, 0x1f00ffff)
nonce: 8 bytes (long)
mvLength: 4 bytes (int, 16)
mutationVector: 16 bytes
```

These are **completely different** structures!

## Solution

### Option 1: Mine Only Genesis Block (Quick Fix)

Force the miner to always mine block 0 (genesis), which is already in PoW format:

```bash
# Edit mine.sh, line 27
HEIGHT=0  # Force mining genesis block only
```

This works because genesis block is already a PoW block. But blockchain won't advance.

### Option 2: Create PoW Block Templates (Proper Solution)

Add a new API endpoint that creates **new PoW block templates** for mining:

```scala
// GET /mining/template
// Returns a NEW PoW block template for height N+1

{
  "version": 1,
  "parentId": "hash_of_block_N",
  "stateRoot": "current_state_root",
  "timestamp": current_time,
  "difficultyBits": "1f00ffff",
  "nonce": 0,
  "mutationVectorLength": 16,
  "height": N + 1
}
```

Then miners work on this template instead of existing blocks.

### Option 3: Hybrid Approach (Best)

Support BOTH mining modes:

1. **Mine existing blocks retroactively** (for testing)
   - Only works with genesis block (height 0)
   - Useful for validating the PoW algorithm

2. **Mine new blocks** (for production)
   - Creates new PoW block templates
   - Builds on top of existing chain
   - Advances blockchain height

## Quick Fix Implementation

For now, let's just mine genesis repeatedly to test the system:

```bash
# Edit mine.sh
HEIGHT=0  # Line 27 - force genesis mining

# Test
./mine.sh
```

**Expected Output**:
```
Mining block 0 with header prefix: 00000001000000000000000000000000...
✅ Found solution: 4a2de176737db50adec3fbcdc8508640
📤 Submitting solution to node...
✅ Solution accepted!  ← THIS SHOULD WORK NOW
```

## Why Genesis Works

Genesis block (block 0) is defined in `Genesis.scala` with PoW format:
- Version: 1 (correct)
- DifficultyBits: 0x1f00ffff (correct)
- MutationVector: 16 bytes (correct)
- All fields match PoW consensus spec

So when you mine genesis, the validation succeeds!

## Implementation Plan for Production

### Step 1: Add Block Template Endpoint

```scala
// In BlockHeaderRoutes.scala

(get & path("mining" / "template")) {
  complete {
    val currentHeight = blockchainUpdater.height
    val parentBlock = blockchainUpdater.lastBlock.get
    
    val template = _root_.consensus.BlockHeader(
      version = 1,
      parentId = parentBlock.id().arr,
      stateRoot = parentBlock.header.transactionsRoot.arr,
      timestamp = System.currentTimeMillis(),
      difficultyBits = 0x1f00ffffL,
      nonce = 0L,
      mutationVector = Array.empty[Byte]  // Empty - miner fills this
    )
    
    MiningTemplateResponse(
      height = currentHeight + 1,
      header_prefix_hex = template.bytes().take(80).map("%02x".format(_)).mkString
    )
  }
}
```

### Step 2: Update Mining Script

```bash
# Fetch template instead of existing block
TEMPLATE=$(curl -s "$NODE_URL/mining/template")
HEIGHT=$(echo "$TEMPLATE" | jq -r .height)
HEADER=$(echo "$TEMPLATE" | jq -r .header_prefix_hex)

# Mine the template
cargo run --release -- --header-hex "$HEADER" ...

# Submit with correct height
curl -X POST "$NODE_URL/mining/submit" -d "{
  \"height\": $HEIGHT,
  \"mutation_vector_hex\": \"$MV\"
}"
```

### Step 3: Update Persistence Logic

When persisting, use `height + 1` (new block) instead of `height` (existing block):

```scala
persister.persistPowBlock(minedHeader, submission.height) // Already at N+1
```

## Testing the Quick Fix

```bash
# 1. Edit mine.sh to force HEIGHT=0

# 2. Start node
java -jar node/target/waves-all-*.jar node/waves-pow.conf

# 3. Run miner
./mine.sh

# Expected: ✅ Solution accepted!
```

## Why This Matters

**Current behavior**: Mining fails on all blocks except genesis
**After fix**: Mining works consistently, blockchain advances properly

## Summary

🔴 **Problem**: Mining Waves PoS blocks (incompatible format)  
🟡 **Quick Fix**: Mine only genesis block (HEIGHT=0)  
🟢 **Proper Solution**: Create PoW block templates for new blocks  

For now, use the quick fix to validate the system works. Then implement template endpoint for production.
