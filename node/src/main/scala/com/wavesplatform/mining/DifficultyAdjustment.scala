package com.wavesplatform.mining

import com.wavesplatform.state.Blockchain

/**
 * Dynamic difficulty adjustment for PoW mining
 * Similar to Bitcoin's difficulty adjustment algorithm
 */
object DifficultyAdjustment {
  
  // Cache to avoid recalculating the same difficulty
  private val difficultyCache = new java.util.concurrent.ConcurrentHashMap[Int, Long]()
  
  // Target block time: 60 seconds
  val TARGET_BLOCK_TIME_MS: Long = 60000L
  
  // Adjust difficulty every N blocks (Bitcoin uses 2016, ~2 weeks at 10min blocks)
  // For 60s blocks, 2016 blocks = ~33.6 hours between adjustments
  val ADJUSTMENT_INTERVAL: Int = 2016
  
  // Initial difficulty (production starting point)
  val INITIAL_DIFFICULTY: Long = 0x1f00ffffL
  
  // Difficulty floor - never go below initial difficulty
  // This prevents difficulty from collapsing during low hashrate periods
  val DIFFICULTY_FLOOR: Long = INITIAL_DIFFICULTY
  
  // Minimum and maximum difficulty bounds
  val MIN_DIFFICULTY: Long = DIFFICULTY_FLOOR
  val MAX_DIFFICULTY: Long = 0xffffffffL
  
  // Maximum adjustment factor per interval (Bitcoin uses ~4x, we use ±25% for stability)
  val MAX_ADJUSTMENT_FACTOR: Double = 1.25  // Can increase by 25% max
  val MIN_ADJUSTMENT_FACTOR: Double = 0.75  // Can decrease by 25% max
  
  /**
   * Calculate the next difficulty based on recent block times
   * 
   * @param blockchain The blockchain to read block history from
   * @param currentHeight The current blockchain height
   * @return The difficulty bits for the next block
   */
  def calculateDifficulty(blockchain: Blockchain, currentHeight: Int): Long = {
    // Use initial difficulty for first blocks
    if (currentHeight < ADJUSTMENT_INTERVAL) {
      return INITIAL_DIFFICULTY
    }
    
    // Check cache first
    Option(difficultyCache.get(currentHeight)) match {
      case Some(cached) if cached != 0 => return cached
      case _ => // Calculate below
    }
    
    // Only adjust at interval boundaries (production: no emergency adjustments)
    if (currentHeight % ADJUSTMENT_INTERVAL != 0) {
      // Between adjustments, maintain the last adjusted difficulty
      // Find the most recent adjustment block
      val lastAdjustmentHeight = (currentHeight / ADJUSTMENT_INTERVAL) * ADJUSTMENT_INTERVAL
      
      if (lastAdjustmentHeight == 0) {
        // Before first adjustment, use initial
        return INITIAL_DIFFICULTY
      }
      
      // Get the difficulty from the last adjustment block (use cache)
      val lastDifficulty = calculateDifficulty(blockchain, lastAdjustmentHeight)
      return lastDifficulty
    }
    
    // Get the last ADJUSTMENT_INTERVAL blocks
    val startHeight = currentHeight - ADJUSTMENT_INTERVAL
    val endHeight = currentHeight - 1
    
    val blocks = (startHeight to endHeight).flatMap { h =>
      blockchain.blockHeader(h)
    }
    
    println(s"\n🔧 Calculating difficulty adjustment at height $currentHeight")
    println(s"   Analyzing blocks $startHeight to $endHeight")
    println(s"   Found ${blocks.length} blocks (need $ADJUSTMENT_INTERVAL)")
    
    if (blocks.length < ADJUSTMENT_INTERVAL) {
      // Not enough blocks, use initial difficulty
      println(s"   ⚠️  Not enough blocks! Using initial difficulty")
      return INITIAL_DIFFICULTY
    }
    
    // Calculate actual time taken for the interval
    val firstBlock = blocks.head
    val lastBlock = blocks.last
    val actualTimeMs = lastBlock.header.timestamp - firstBlock.header.timestamp
    
    // Expected time for the interval
    val expectedTimeMs = TARGET_BLOCK_TIME_MS * ADJUSTMENT_INTERVAL
    
    // Calculate adjustment ratio
    val ratio = actualTimeMs.toDouble / expectedTimeMs.toDouble
    
    // Get current difficulty (for now use initial, later store in block)
    val currentDifficulty = INITIAL_DIFFICULTY
    
    // Calculate new difficulty with bounds
    val adjustmentFactor = if (ratio < MIN_ADJUSTMENT_FACTOR) {
      // Blocks too fast, make harder
      MIN_ADJUSTMENT_FACTOR
    } else if (ratio > MAX_ADJUSTMENT_FACTOR) {
      // Blocks too slow, make easier
      MAX_ADJUSTMENT_FACTOR
    } else {
      ratio
    }
    
    // Apply adjustment: difficulty decreases when blocks are too fast
    // (smaller number = harder to find)
    val newDifficulty = (currentDifficulty * adjustmentFactor).toLong
    
    // Clamp to bounds (enforce difficulty floor)
    val clampedDifficulty = Math.max(MIN_DIFFICULTY, Math.min(MAX_DIFFICULTY, newDifficulty))
    
    // Production logging
    val actualBlockTime = actualTimeMs / ADJUSTMENT_INTERVAL
    println(s"🔧 Difficulty adjustment at height $currentHeight:")
    println(s"   Target time: ${TARGET_BLOCK_TIME_MS}ms/block")
    println(s"   Actual time: ${actualBlockTime}ms/block")
    println(s"   Adjustment: ${if (adjustmentFactor > 1) "+" else ""}${((adjustmentFactor - 1) * 100).toInt}%")
    println(s"   Old difficulty: ${difficultyDescription(currentDifficulty)}")
    println(s"   New difficulty: ${difficultyDescription(clampedDifficulty)}")
    
    // Cache the result
    difficultyCache.put(currentHeight, clampedDifficulty)
    
    clampedDifficulty
  }
  
  /**
   * Get a human-readable difficulty description
   */
  def difficultyDescription(difficulty: Long): String = {
    val ratio = INITIAL_DIFFICULTY.toDouble / difficulty.toDouble
    f"0x${difficulty}%08x (${ratio}%.2fx base difficulty)"
  }
  
  /**
   * Calculate expected hashrate based on difficulty and block time
   */
  def estimatedHashrate(difficulty: Long, blockTimeMs: Long): Double = {
    val targetHashes = Math.pow(2, 32) / difficulty.toDouble
    val hashesPerSecond = targetHashes / (blockTimeMs / 1000.0)
    hashesPerSecond
  }
}
