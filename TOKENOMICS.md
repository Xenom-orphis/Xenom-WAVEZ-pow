# Waves PoW Tokenomics 💰

## **Reward Schedule**

### **Initial Parameters**
- **Initial Block Reward**: 3 WAVES
- **Halving Interval**: Every 210,000 blocks (~4 years at 60s/block)
- **Target Block Time**: 60 seconds (enforced minimum)
- **Genesis Supply**: 100,000,000 WAVES

### **Halving Schedule**

| Era | Blocks | Reward | Est. Years | Coins Mined | Total Supply |
|-----|--------|--------|------------|-------------|--------------|
| 0 (Genesis) | 0 | - | - | - | 100,000,000 |
| 1 | 1 - 210,000 | 3.00 WAVES | 0-4 | 630,000 | 100,630,000 |
| 2 | 210,001 - 420,000 | 1.50 WAVES | 4-8 | 315,000 | 100,945,000 |
| 3 | 420,001 - 630,000 | 0.75 WAVES | 8-12 | 157,500 | 101,102,500 |
| 4 | 630,001 - 840,000 | 0.375 WAVES | 12-16 | 78,750 | 101,181,250 |
| 5 | 840,001 - 1,050,000 | 0.1875 WAVES | 16-20 | 39,375 | 101,220,625 |
| ... | ... | ... | ... | ... | ... |
| 64+ | 13,440,000+ | 0 WAVES | 256+ | 0 | ~101,260,000 |

### **Maximum Supply**
**~101,260,000 WAVES** (100M genesis + ~1.26M mined)

## **Supply Dynamics**

### **Year-by-Year Projection**

```
Year 1:  100,630,000 WAVES (+0.63%)
Year 2:  100,945,000 WAVES (+0.31%)  ← Halving at ~4 years
Year 4:  101,102,500 WAVES (+0.16%)
Year 8:  101,181,250 WAVES (+0.08%)
Year 20: 101,257,500 WAVES (+0.01%)
Year 50: ~101,260,000 WAVES (≈max supply)
```

### **Inflation Rate**
- **Initial**: 0.63% annually
- **After 1st halving**: 0.31% annually
- **After 2nd halving**: 0.16% annually
- **Long-term**: Approaches 0%

## **Economic Model**

### **Bitcoin-Style Scarcity**
✅ Fixed maximum supply (~101.26M)  
✅ Predictable emission schedule  
✅ Decreasing inflation over time  
✅ Long-term deflationary pressure  

### **Key Differences from Bitcoin**
| Feature | Waves PoW | Bitcoin |
|---------|-----------|---------|
| Genesis Supply | 100M WAVES | 0 BTC |
| Initial Reward | 3 WAVES | 50 BTC |
| Block Time | 60s (enforced) | ~600s (target) |
| Halving Interval | 210,000 blocks (~4 years) | 210,000 blocks (~4 years) |
| Max Supply | ~101.26M WAVES | 21M BTC |
| Supply Model | Genesis + Mining | Pure Mining |

## **Mining Economics**

### **Block Time Enforcement**
- **Minimum**: 60 seconds between blocks (hard requirement)
- **Rejected**: Blocks submitted <60s after parent
- **Purpose**: Prevents rapid mining and maintains predictable emission

### **Era 1 Economics** (Blocks 1-210,000)
```
Daily:    1,440 blocks × 3 WAVES = 4,320 WAVES/day
Monthly:  43,200 blocks × 3 WAVES = 129,600 WAVES/month
Yearly:   525,600 blocks × 3 WAVES = 1,576,800 WAVES/year (capped at 210k blocks)
Per Era:  210,000 blocks × 3 WAVES = 630,000 WAVES total
```

### **Reward Calculation**
```scala
initialReward = 3 WAVES
halvingInterval = 210,000 blocks
halvings = (height - 1) / halvingInterval

reward = if (halvings >= 64) {
  0 WAVES  // Max supply reached
} else {
  initialReward / (2^halvings)
}
```

## **Network Security**

### **Proof of Work Parameters**
- **Algorithm**: Genetic PoW (mutation vector optimization)
- **Difficulty Adjustment**: Every 2,016 blocks (~33.6 hours)
- **Target Block Time**: 60 seconds
- **Initial Difficulty**: 0x1f00ffff
- **Adjustment Range**: ±25% per period
- **Difficulty Floor**: 0x1f00ffff (minimum)

### **Mining Requirements**
- **Balance**: None required (permissionless)
- **Hardware**: CPU/GPU (genetic algorithm miner)
- **Network**: Internet connection for template/submission

## **Governance Implications**

### **Pre-mine**: 100M WAVES (Genesis allocation)
- Controlled by genesis address: `3M4qwDomRabJKLZxuXhwfqLApQkU592nWxF`
- Represents ~98.75% of max supply
- Could be distributed via ICO, airdrop, or treasury

### **Fair Launch Alternative**
To eliminate pre-mine, set genesis `initial-balance: 0`:
```hocon
genesis {
  initial-balance: 0
  transactions = []
}
```
This creates pure PoW chain (0 genesis + 1.26M mined = 1.26M max supply)

## **Transaction Fees**
- Separate from block rewards
- Go to miners (standard Waves fee structure)
- Provide additional incentive beyond coinbase

## **Comparison to Original Waves (PoS)**

| Feature | Waves PoW | Waves Original |
|---------|-----------|----------------|
| Consensus | Proof of Work | Proof of Stake (LPoS) |
| Mining Reward | Yes (halving) | No (fee-only) |
| Balance Required | No | Yes (for staking) |
| Initial Supply | 100M | 100M (ICO) |
| Max Supply | ~101.26M | 100M (fixed) |
| Inflation | Decreasing to 0% | 0% (no emission) |
| Difficulty | Dynamic (±25%) | N/A |
| Block Time | 60s (enforced) | ~60s (target) |

## **Implementation Details**

### **Code Locations**
- **Reward Logic**: `node/src/main/scala/com/wavesplatform/state/diffs/BlockDiffer.scala`
- **Block Time**: `node/src/main/scala/com/wavesplatform/state/appender/package.scala`
- **Genesis Config**: `node/waves-pow.conf`
- **Difficulty**: `node/src/main/scala/com/wavesplatform/mining/DifficultyAdjustment.scala`

### **Halving Marker**
PoW blocks are identified by: `block.header.rewardVote == -1`

---

**Built on**: Waves Platform v1.5.11  
**Network**: Custom PoW Chain (Blockchain ID: R)  
**Launch**: October 2025
