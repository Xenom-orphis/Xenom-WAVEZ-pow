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
  
  // Real-time adjustment: Look at recent N blocks for difficulty calculation
  // Shorter window = faster response to hashrate changes
  val ADJUSTMENT_WINDOW: Int = 60  // Last 60 blocks (~60 minutes of history)
  
  // Initial difficulty (production starting point)
  val INITIAL_DIFFICULTY: Long = 0x1f00ffffL
  
  // Difficulty floor - never go below initial difficulty
  val DIFFICULTY_FLOOR: Long = INITIAL_DIFFICULTY
  
  // Minimum and maximum difficulty bounds
  val MIN_DIFFICULTY: Long = DIFFICULTY_FLOOR
  val MAX_DIFFICULTY: Long = 0xffffffffL
  
  // Per-block adjustment limits (smoother than Bitcoin's ±25%)
  // Real-time adjustment allows smaller, more frequent changes
  val MAX_ADJUSTMENT_FACTOR: Double = 1.10  // Max +10% per block
  val MIN_ADJUSTMENT_FACTOR: Double = 0.90  // Max -10% per block
  
  /**
   * Calculate the next difficulty based on recent block times
   * 
   * @param blockchain The blockchain to read block history from
   * @param currentHeight The current blockchain height
   * @return The difficulty bits for the next block
   */
  def calculateDifficulty(blockchain: Blockchain, currentHeight: Int): Long = {
    // Use initial difficulty for first blocks (need history for calculation)
    if (currentHeight <= ADJUSTMENT_WINDOW) {
      return INITIAL_DIFFICULTY
    }
    
    // Check cache first
    Option(difficultyCache.get(currentHeight)) match {
      case Some(cached) if cached != 0 => return cached
      case _ => // Calculate below
    }
    
    // Real-time difficulty: Look at recent ADJUSTMENT_WINDOW blocks
    val startHeight = currentHeight - ADJUSTMENT_WINDOW
    val endHeight = currentHeight - 1
    
    val blocks = (startHeight to endHeight).flatMap { h =>
      blockchain.blockHeader(h)
    }
    
    if (blocks.length < ADJUSTMENT_WINDOW) {
      // Not enough blocks, use initial difficulty
      return INITIAL_DIFFICULTY
    }
    
    // Calculate actual time taken for recent blocks
    val firstBlock = blocks.head
    val lastBlock = blocks.last
    val actualTimeMs = lastBlock.header.timestamp - firstBlock.header.timestamp
    
    // Expected time for the window
    val expectedTimeMs = TARGET_BLOCK_TIME_MS * ADJUSTMENT_WINDOW
    
    // Get previous block's difficulty (what we're adjusting from)
    // Use recursion to get previous difficulty (cached, so efficient)
    val currentDifficulty = if (currentHeight > ADJUSTMENT_WINDOW + 1) {
      calculateDifficulty(blockchain, currentHeight - 1)
    } else {
      INITIAL_DIFFICULTY
    }
    
    // Calculate adjustment ratio (how fast/slow blocks are coming)
    val ratio = expectedTimeMs.toDouble / actualTimeMs.toDouble  // Inverted: >1 means fast, <1 means slow
    
    // Apply adjustment factor with per-block limits
    // ratio > 1 = blocks too fast → increase difficulty (multiply)
    // ratio < 1 = blocks too slow → decrease difficulty (divide)
    val adjustmentFactor = if (ratio > MAX_ADJUSTMENT_FACTOR) {
      MAX_ADJUSTMENT_FACTOR  // Cap maximum increase
    } else if (ratio < MIN_ADJUSTMENT_FACTOR) {
      MIN_ADJUSTMENT_FACTOR  // Cap maximum decrease
    } else {
      ratio  // Use actual ratio if within bounds
    }
    
    // Apply adjustment: difficulty decreases when blocks are too fast
    // (smaller number = harder to find)
    val newDifficulty = (currentDifficulty * adjustmentFactor).toLong
    
    // Clamp to bounds (enforce difficulty floor)
    val clampedDifficulty = Math.max(MIN_DIFFICULTY, Math.min(MAX_DIFFICULTY, newDifficulty))
    
    // Real-time adjustment logging (every block)
    val actualBlockTime = actualTimeMs / ADJUSTMENT_WINDOW
    val changePercent = ((adjustmentFactor - 1) * 100)
    
    // Only log significant changes or periodically
    if (Math.abs(changePercent) > 1.0 || currentHeight % 10 == 0) {
      println(s"⚡ Real-time difficulty adjustment at height $currentHeight:")
      println(f"   Last $ADJUSTMENT_WINDOW blocks: ${actualBlockTime}%.1fms/block (target: ${TARGET_BLOCK_TIME_MS}ms)")
      println(f"   Adjustment: ${if (adjustmentFactor > 1) "+" else ""}$changePercent%.2f%%")
      println(s"   Old: ${difficultyDescription(currentDifficulty)}")
      println(s"   New: ${difficultyDescription(clampedDifficulty)}")
    }
    
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
