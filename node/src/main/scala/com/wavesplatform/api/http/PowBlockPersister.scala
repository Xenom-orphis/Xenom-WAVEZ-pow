package com.wavesplatform.api.http

import com.wavesplatform.block.{Block, SignedBlockHeader}
import com.wavesplatform.common.state.ByteStr
import com.wavesplatform.crypto
import com.wavesplatform.lang.ValidationError
import com.wavesplatform.settings.WavesSettings
import com.wavesplatform.state.Blockchain
import com.wavesplatform.transaction.BlockchainUpdater
import com.wavesplatform.utils.{ScorexLogging, Time}
import com.wavesplatform.wallet.Wallet
import monix.eval.Task
import monix.execution.Scheduler

import scala.concurrent.Await
import scala.concurrent.duration.*

/**
 * Handles persistence of PoW-mined blocks to the blockchain.
 */
class PowBlockPersister(
    blockchainUpdater: BlockchainUpdater & Blockchain,
    wallet: Wallet,
    time: Time,
    settings: WavesSettings,
    blockAppender: Block => Task[Either[ValidationError, Unit]],
    scheduler: Scheduler
) extends ScorexLogging {

  /**
   * Constructs a Waves Block from a PoW consensus.BlockHeader and persists it to the blockchain.
   * 
   * @param powHeader The validated PoW block header
   * @param height The height at which to insert this block
   * @return Either validation error or success
   */
  def persistPowBlock(powHeader: _root_.consensus.BlockHeader, height: Long): Either[ValidationError, String] = {
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
      
      // Get baseTarget from parent (Waves PoS consensus requirement)
      // We cannot arbitrarily set baseTarget - it must follow Waves' PoS rules
      val baseTarget = parentBlockOpt match {
        case Some(parent) => parent.header.baseTarget  // Inherit from parent
        case None => 153722867L  // Genesis baseTarget from Waves
      }

      // Get generator account from wallet
      val generator = wallet.privateKeyAccounts.headOption.getOrElse {
        return Left(com.wavesplatform.transaction.TxValidationError.GenericError("No accounts in wallet for block signing"))
      }

      // Generate VRF proof for version 5 blocks
      // We need to use the blockchain's hitSource calculation (not just parent's generationSignature)
      val hitSource = blockchainUpdater.hitSource((height - 1).toInt) match {
        case Some(hitSrc) => hitSrc
        case None => ByteStr(Array.fill(32)(0.toByte))  // Genesis hit source
      }
      
      // Sign VRF using wallet private key
      val vrfProof = crypto.signVRF(generator.privateKey, hitSource.arr)
      
      // For PoW mining: disregard PoS timing rules, use current time
      // This allows fast block generation based on PoW solution speed
      val blockTimestamp = System.currentTimeMillis()
      
      log.info(s"   Using current timestamp: $blockTimestamp (PoS timing disregarded for PoW)")

      // PoW blocks: empty transactions, rewards handled separately
      // Keep rewardVote = -1 as PoW marker for PoS bypass
      val transactions = Seq.empty
      val txRoot = com.wavesplatform.block.mkTransactionsRoot(5.toByte, transactions)

      // Create Waves BlockHeader
      // Note: We need to map PoW fields to Waves PoS fields
      // IMPORTANT: Waves blockchain requires version 5 blocks with VRF
      val wavesHeader = com.wavesplatform.block.BlockHeader(
        version = 5.toByte,  // Version 5 required by blockchain
        timestamp = blockTimestamp,  // Current time - ignore PoS delay rules
        reference = parentReference,
        baseTarget = baseTarget,  // Use parent's baseTarget (PoS consensus rule)
        generationSignature = vrfProof,  // Valid VRF proof
        generator = generator.publicKey,
        featureVotes = Seq.empty,
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
      log.info(s"   Generator: ${generator.publicKey.toString.take(16)}...")
      log.info(s"   Generator Address: ${generator.toAddress}")
      log.info(s"   MV: ${powHeader.mutationVector.map("%02x".format(_)).mkString}")
      log.info(s"   Signature: ${signature.toString.take(16)}...")
      log.info(s"   💰 Mining Reward: 6 WAVES (credited by BlockchainUpdater)")

      // Append to blockchain
      val appendTask = blockAppender(block)
      val result = Await.result(appendTask.runToFuture(scheduler), 10.seconds)

      result match {
        case Right(_) =>
          log.info(s"✅ PoW block successfully added to blockchain at height ${blockchainUpdater.height}")
          Right(block.id().toString)
        case Left(error) =>
          log.error(s"❌ Failed to append PoW block: $error")
          Left(error)
      }
    } catch {
      case e: Exception =>
        log.error(s"❌ Exception while persisting PoW block: ${e.getMessage}", e)
        Left(com.wavesplatform.transaction.TxValidationError.GenericError(s"Failed to persist block: ${e.getMessage}"))
    }
  }

  // Note: We no longer convert PoW difficulty to baseTarget
  // Instead, we inherit baseTarget from parent block to maintain Waves PoS consensus rules
}
