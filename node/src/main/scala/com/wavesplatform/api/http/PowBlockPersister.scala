package com.wavesplatform.api.http

import com.wavesplatform.block.Block
import com.wavesplatform.common.state.ByteStr
import com.wavesplatform.crypto
import com.wavesplatform.lang.ValidationError
import com.wavesplatform.network.{BlockForged, ChannelGroupExt}
import com.wavesplatform.state.Blockchain
import com.wavesplatform.transaction.BlockchainUpdater
import com.wavesplatform.utils.ScorexLogging
import com.wavesplatform.wallet.Wallet
import io.netty.channel.group.ChannelGroup
import monix.eval.Task
import monix.execution.Scheduler

import scala.concurrent.Await
import scala.concurrent.duration.DurationInt
/**
 * Handles persistence of PoW-mined blocks to the blockchain.
 */
class PowBlockPersister(
    blockchainUpdater: BlockchainUpdater & Blockchain,
    blockAppender: Block => Task[Either[ValidationError, Option[BigInt]]],
    wallet: Wallet,
    allChannels: ChannelGroup,
    scheduler: Scheduler
) extends ScorexLogging {

  /**
   * Constructs a Waves Block from a PoW consensus.BlockHeader and persists it to the blockchain.
   * 
   * @param height The height at which to insert this block
   * @param minerAddress Optional miner address to receive rewards (if None, uses node wallet)
   * @return Either validation error or success
   */
  def persistPowBlock(powHeader: _root_.consensus.BlockHeader, height: Long, minerAddress: Option[String] = None): Either[ValidationError, String] = {
    try {
      // Get the parent block for reference
      val parentBlockOpt = if (height > 0) {
        blockchainUpdater.blockHeader((height - 1).toInt)
      } else {
        None
      }

      val parentReference = parentBlockOpt match {
        case Some(parent) => parent.id()
        case None => ByteStr(Array.fill(32)(0.toByte)) // Genesis parent
      }
      
      // For PoW blocks: Store difficulty in baseTarget field
      // This allows consensus validation to check difficulty
      val baseTarget = powHeader.difficultyBits

      // Get generator account from wallet
      wallet.privateKeyAccounts.headOption match {
        case None => 
          return Left(com.wavesplatform.transaction.TxValidationError.GenericError("No accounts in wallet for block signing"))
        case Some(generator) =>
          // For PoW blocks: Store mutation vector in generationSignature field (16 bytes)
          // Pad to 32 bytes for Waves compatibility
          val mutationVectorPadded = powHeader.mutationVector ++ Array.fill(16)(0.toByte)
          val generationSigForPoW = ByteStr(mutationVectorPadded)
          
          // CRITICAL: Use timestamp from PoW header (the template timestamp)
          // Miner solved PoW with this exact timestamp - changing it breaks validation!
          val blockTimestamp = powHeader.timestamp
          
          log.info(s"   Using PoW header timestamp: $blockTimestamp (matches template and solution)")

          // PoW blocks: empty transactions, rewards handled separately
          // Keep rewardVote = -1 as PoW marker for PoS bypass
          val transactions = Seq.empty
          val txRoot = com.wavesplatform.block.mkTransactionsRoot(6.toByte, transactions)

          // Encode miner address in feature votes if provided
          // Format: Store address bytes as sequence of shorts (2 bytes each)
          val featureVotes: Seq[Short] = minerAddress match {
            case Some(addr) =>
              com.wavesplatform.account.Address.fromString(addr) match {
                case Right(address) =>
                  val addressBytes = address.bytes
                  // Convert bytes to shorts (pack 2 bytes per short)
                  addressBytes.grouped(2).map { pair =>
                    val high = (pair(0) & 0xFF) << 8
                    val low = if (pair.length > 1) (pair(1) & 0xFF) else 0
                    (high | low).toShort
                  }.toSeq
                case Left(_) => Seq.empty
              }
            case None => Seq.empty
          }

          // Create Waves BlockHeader with PoW data embedded
          // CRITICAL: Store PoW validation data in block for consensus
          // - baseTarget: difficulty bits (normally PoS target, repurposed for PoW)
          // - generationSignature: mutation vector (16 bytes + 16 padding)
          // - featureVotes: miner address (if external miner)
          val wavesHeader = com.wavesplatform.block.BlockHeader(
            version = 6.toByte,  // Version 6 = PoW blocks (uses difficulty for score)
            timestamp = blockTimestamp,  // Current time - ignore PoS delay rules
            reference = parentReference,
            baseTarget = baseTarget,  // PoW: difficulty bits (was PoS base target)
            generationSignature = generationSigForPoW,  // PoW: mutation vector (was VRF proof)
            generator = generator.publicKey,
            featureVotes = featureVotes,  // PoW: miner address (if external)
            rewardVote = -1L,  // PoW marker: bypasses PoS validation
            transactionsRoot = txRoot,  // Empty transactions root
            stateHash = None,  // State hash not supported yet
            challengedHeader = None
          )

          // Serialize header for signing  
          val headerBytes = com.wavesplatform.block.serialization.BlockHeaderSerializer.toBytes(wavesHeader)
          
          // Sign the block
          val signature = crypto.sign(generator.privateKey, headerBytes)

          // Create the block (empty transactions)
          val block = Block(
            header = wavesHeader,
            signature = signature,
            transactionData = transactions  // Empty - rewards handled by protocol
          )

          // Log block details
          log.info(s"🔨 Constructed PoW block for persistence:")
          log.info(s"   Height: $height")
          log.info(s"   Parent: ${parentReference.toString.take(16)}...")
          log.info(s"   Block Signer: ${generator.toAddress}")
          log.info(s"   Miner Address (rewards): ${minerAddress.getOrElse(generator.toAddress.toString)}")
          log.info(s"   MV: ${powHeader.mutationVector.map("%02x".format(_)).mkString}")
          log.info(s"   Signature: ${signature.toString.take(16)}...")
          
          // Calculate halving reward for logging
          val initialReward = 3L * com.wavesplatform.settings.Constants.UnitsInWave
          val halvingInterval = 210000
          val halvings = (height - 1) / halvingInterval
          val powReward = if (halvings >= 64) 0L else initialReward >> halvings
          val rewardWaves = powReward.toDouble / com.wavesplatform.settings.Constants.UnitsInWave
          log.info(f"   💰 Mining Reward: $rewardWaves%.8f WAVES (halving era $halvings, credited by BlockchainUpdater)")

          // Append to blockchain
          val appendTask = blockAppender(block)
          val result = Await.result(appendTask.runToFuture(using scheduler), 10.seconds)

          result match {
            case Right(_) =>
              log.info(s"✅ PoW block successfully added to blockchain at height ${blockchainUpdater.height}")
              
              // Broadcast to network peers (like regular PoS miner does)
              if (blockchainUpdater.isLastBlockId(block.id())) {
                allChannels.broadcast(BlockForged(block))
                log.info(s"📡 Broadcast PoW block ${block.id().toString.take(16)}... to network peers")
              }
              
              Right(block.id().toString)
            case Left(err) =>
              log.error(s"❌ Failed to append PoW block: $err")
              Left(err)
          }
      } // Close match block for generator
    } catch {
      case e: Exception =>
        log.error(s"❌ Exception while persisting PoW block: ${e.getMessage}", e)
        Left(com.wavesplatform.transaction.TxValidationError.GenericError(s"Failed to persist block: ${e.getMessage}"))
    }
  }

  // Note: We no longer convert PoW difficulty to baseTarget
  // Instead, we inherit baseTarget from parent block to maintain Waves PoS consensus rules
}
