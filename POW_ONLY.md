# Pure PoW Mining - PoS Disabled

## Overview

This blockchain uses **ONLY Proof-of-Work (PoW) mining**. The Waves built-in PoS miner is completely disabled.

## Mining Architecture

```
┌──────────────────────────────────────────────────┐
│              Mining System Architecture           │
├──────────────────────────────────────────────────┤
│                                                   │
│  ❌ PoS Mining (DISABLED)                        │
│     ├─ Built-in Waves miner: enable = no         │
│     ├─ Generation delay: 999999 days             │
│     └─ Result: No PoS blocks created             │
│                                                   │
│  ✅ PoW Mining (ACTIVE)                          │
│     ├─ External miner (mine.sh)                  │
│     ├─ Genetic algorithm + BLAKE3                │
│     ├─ Template-based mining API                 │
│     └─ Submits blocks via REST API               │
│                                                   │
│  Block Creation Flow:                            │
│     1. External miner requests template          │
│     2. Miner solves PoW puzzle                   │
│     3. Submit solution to node                   │
│     4. Node validates and adds block             │
│     5. Miner receives 6 WAVES reward             │
│                                                   │
└──────────────────────────────────────────────────┘
```

## Configuration

### PoS Miner (Disabled)

In `waves-pow.conf`:

```hocon
miner {
  # Disable PoS mining - only PoW mining via API
  enable = no
  interval-after-last-block-then-generation-is-allowed = 999999d
  quorum = 0
}
```

**Key Settings:**
- `enable = no` - Explicitly disables the miner
- `interval-after-last-block-then-generation-is-allowed = 999999d` - Prevents any PoS mining attempts
- `quorum = 0` - No peer consensus needed for PoW blocks

### PoW Validation Bypass

In the node code, PoW blocks (marked with `rewardVote = -1`) bypass all PoS validation:

```scala
// appender/package.scala
isPowBlock = block.header.rewardVote == -1L

// Skip PoS checks
validateBaseTarget        ← Skipped ✅
validateGenerationSignature (VRF) ← Skipped ✅
validateBlockDelay        ← Skipped ✅
```

## Why PoS is Disabled

1. **No Competition**: PoS and PoW shouldn't compete for blocks
2. **Fast Mining**: PoW drives block speed, not PoS timing rules
3. **Clean Architecture**: One consensus mechanism, not hybrid
4. **Predictable Rewards**: Only PoW miners get rewards

## Block Types

| Type | Marker | Generation | Validation | Rewards |
|------|--------|------------|------------|---------|
| **PoS** | `rewardVote > 0` | ❌ Disabled | Full PoS rules | N/A |
| **PoW** | `rewardVote = -1` | ✅ External miner | PoS bypassed | 6 WAVES |

## Verification

### Check PoS Miner Status

```bash
# Node logs should show:
# NO "Mining new block" messages from PoS miner
# ONLY "Valid PoW solution found" from API

# Check recent blocks
curl http://127.0.0.1:36669/blocks/last | jq .rewardVote

# Output should be: -1 (PoW marker)
```

### Check Block Generation

```bash
# All blocks should have rewardVote = -1
curl -s http://127.0.0.1:36669/blocks/seq/1000/1010 | jq '.[].rewardVote'

# Expected: All values = -1
```

## How to Mine (PoW Only)

```bash
# 1. Start the node
java -jar node/target/waves-all-*.jar node/waves-pow.conf

# 2. Run the PoW miner
./mine.sh

# 3. Watch blocks being created
tail -f ~/.waves-pow/waves.log | grep "PoW"
```

**Expected Output:**
```
INFO  ✅ Valid PoW solution found for block 1100!
INFO  🔨 Constructed PoW block for persistence
INFO  ✅ PoW block successfully added to blockchain at height 1100
INFO  💰 PoW Mining Reward: Credited 6 WAVES to 3M4q...
```

## Summary

```
┌────────────────────────────────────────────┐
│     Pure PoW Blockchain - No PoS Mining    │
├────────────────────────────────────────────┤
│                                             │
│  ✅ PoS Miner: Disabled                    │
│  ✅ PoW Miner: Active (External)           │
│  ✅ Block Validation: PoS bypassed         │
│  ✅ Mining Rewards: PoW only (6 WAVES)     │
│  ✅ Block Speed: PoW-driven                │
│                                             │
│  Result: Clean, pure PoW blockchain! 🎯    │
│                                             │
└────────────────────────────────────────────┘
```

**No PoS competition. Only PoW mining. Fast and clean.** 🚀
