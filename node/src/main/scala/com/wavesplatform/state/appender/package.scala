package com.wavesplatform.state

import cats.syntax.either.*
import com.wavesplatform.block.Block.BlockId
import com.wavesplatform.block.{Block, BlockSnapshot}
import com.wavesplatform.common.state.ByteStr
import com.wavesplatform.consensus.PoSSelector
import com.wavesplatform.lang.ValidationError
import com.wavesplatform.metrics.*
import com.wavesplatform.mining.Miner
import com.wavesplatform.network.BlockSnapshotResponse
import com.wavesplatform.protobuf.PBSnapshots
import com.wavesplatform.state.BlockchainUpdaterImpl.BlockApplyResult
import com.wavesplatform.state.BlockchainUpdaterImpl.BlockApplyResult.Applied
import com.wavesplatform.transaction.*
import com.wavesplatform.transaction.TxValidationError.{BlockAppendError, BlockFromFuture, GenericError}
import com.wavesplatform.utils.{LoggerFacade, Time}
import com.wavesplatform.utx.UtxPool
import kamon.Kamon

package object appender {

  val MaxTimeDrift: Long = 100 // millis

  // Invalid blocks, that are already in blockchain
  private val exceptions = List(
    812608 -> ByteStr.decodeBase58("2GNCYVy7k3kEPXzz12saMtRDeXFKr8cymVsG8Yxx3sZZ75eHj9csfXnGHuuJe7XawbcwjKdifUrV1uMq4ZNCWPf1").get,
    813207 -> ByteStr.decodeBase58("5uZoDnRKeWZV9Thu2nvJVZ5dBvPB7k2gvpzFD618FMXCbBVBMN2rRyvKBZBhAGnGdgeh2LXEeSr9bJqruJxngsE7").get
  )

  private def responseToSnapshot(block: Block, height: Int)(s: BlockSnapshotResponse): BlockSnapshot =
    BlockSnapshot(
      block.id(),
      block.transactionData.zip(s.snapshots).map { case (tx, pbs) => PBSnapshots.fromProtobuf(pbs, tx.id(), height) }
    )

  private[appender] def appendKeyBlock(
      blockchainUpdater: BlockchainUpdater & Blockchain,
      utx: UtxPool,
      pos: PoSSelector,
      time: Time,
      log: LoggerFacade,
      verify: Boolean,
      txSignParCheck: Boolean
  )(block: Block, snapshot: Option[BlockSnapshotResponse]): Either[ValidationError, BlockApplyResult] =
    for {
      hitSource <- if (verify) validateBlock(blockchainUpdater, pos, time)(block) else pos.validateGenerationSignature(block)
      newHeight <-
        metrics.appendBlock
          .measureSuccessful(
            blockchainUpdater
              .processBlock(block, hitSource, snapshot.map(responseToSnapshot(block, blockchainUpdater.height + 1)), None, verify, txSignParCheck)
          )
          .map {
            case res @ Applied(discardedDiffs, _) =>
              // TODO: move UTX cleanup from appender
              if (block.transactionData.nonEmpty) {
                utx.removeAll(block.transactionData)
                log.trace(
                  s"Removing txs of ${block.id()} ${block.transactionData.map(_.id()).mkString("(", ", ", ")")} from UTX pool"
                )
              }
              utx.setPrioritySnapshots(discardedDiffs)
              utx.scheduleCleanup()
              res
            case res => res
          }
    } yield newHeight

  private[appender] def appendExtensionBlock(
      blockchainUpdater: BlockchainUpdater & Blockchain,
      pos: PoSSelector,
      time: Time,
      verify: Boolean,
      txSignParCheck: Boolean
  )(block: Block, snapshot: Option[BlockSnapshotResponse]): Either[ValidationError, (BlockApplyResult, Int)] = {
    if (block.header.challengedHeader.nonEmpty) {
      processBlockWithChallenge(blockchainUpdater, pos, time, verify, txSignParCheck)(block, snapshot)
    } else {
      for {
        hitSource <- if (verify) validateBlock(blockchainUpdater, pos, time)(block) else pos.validateGenerationSignature(block)
        applyResult <- metrics.appendBlock.measureSuccessful(
          blockchainUpdater.processBlock(
            block,
            hitSource,
            snapshot.map(responseToSnapshot(block, blockchainUpdater.height + 1)),
            None,
            verify,
            txSignParCheck
          )
        )
      } yield applyResult -> blockchainUpdater.height
    }
  }

  private[appender] def appendChallengeBlock(
      blockchainUpdater: BlockchainUpdater & Blockchain,
      utx: UtxPool,
      pos: PoSSelector,
      time: Time,
      log: LoggerFacade,
      verify: Boolean,
      txSignParCheck: Boolean
  )(block: Block, snapshot: Option[BlockSnapshotResponse]): Either[ValidationError, BlockApplyResult] =
    processBlockWithChallenge(blockchainUpdater, pos, time, verify, txSignParCheck)(block, snapshot).map {
      case (res @ Applied(discardedDiffs, _), _) =>
        if (block.transactionData.nonEmpty) {
          utx.removeAll(block.transactionData)
          log.trace(
            s"Removing txs of ${block.id()} ${block.transactionData.map(_.id()).mkString("(", ", ", ")")} from UTX pool"
          )
        }
        utx.setPrioritySnapshots(discardedDiffs)
        utx.scheduleCleanup()
        res
      case (res, _) => res
    }

  private def processBlockWithChallenge(
      blockchainUpdater: BlockchainUpdater & Blockchain,
      pos: PoSSelector,
      time: Time,
      verify: Boolean,
      txSignParCheck: Boolean
  )(block: Block, snapshot: Option[BlockSnapshotResponse]): Either[ValidationError, (BlockApplyResult, Int)] = {
    val challengedBlock = block.toOriginal
    for {
      challengedHitSource <-
        if (verify) validateBlock(blockchainUpdater, pos, time)(challengedBlock) else pos.validateGenerationSignature(challengedBlock)
      hitSource <- if (verify) validateBlock(blockchainUpdater, pos, time)(block) else pos.validateGenerationSignature(block)
      applyResult <-
        metrics.appendBlock
          .measureSuccessful(
            blockchainUpdater.processBlock(
              block,
              hitSource,
              snapshot.map(responseToSnapshot(block, blockchainUpdater.height + 1)),
              Some(challengedHitSource),
              verify,
              txSignParCheck
            )
          )
    } yield applyResult -> blockchainUpdater.height
  }

  private def validateBlock(blockchainUpdater: Blockchain, pos: PoSSelector, time: Time)(block: Block) =
    for {
      _ <- Miner.isAllowedForMining(block.sender.toAddress, blockchainUpdater).leftMap(BlockAppendError(_, block))
      hitSource <- blockConsensusValidation(blockchainUpdater, pos, time.correctedTime(), block) { (height, parent) =>
        // Skip balance check for PoW blocks (rewardVote = -1 marker)
        if (block.header.rewardVote == -1) {
          Right(0L)  // PoW blocks don't need balance
        } else {
          val balance = blockchainUpdater.generatingBalance(block.sender.toAddress, Some(parent))
          Either.cond(
            blockchainUpdater.isEffectiveBalanceValid(height, block, balance),
            balance + block.header.challengedHeader.map(ch => blockchainUpdater.generatingBalance(ch.generator.toAddress, Some(parent))).getOrElse(0L),
            s"generator's effective balance $balance is less that required for generation"
          )
        }
      }
      _ <- validateStateHash(block, blockchainUpdater)
      _ <- validateChallengedHeader(block, blockchainUpdater)
    } yield hitSource

  private def blockConsensusValidation(blockchain: Blockchain, pos: PoSSelector, currentTs: Long, block: Block)(
      genBalance: (Int, BlockId) => Either[String, Long]
  ): Either[ValidationError, ByteStr] =
    metrics.blockConsensusValidation
      .measureSuccessful {

        val blockTime = block.header.timestamp

        for {
          height <- blockchain
            .heightOf(block.header.reference)
            .toRight(GenericError(s"height: history does not contain parent ${block.header.reference}"))
          parent <- blockchain.parentHeader(block.header).toRight(GenericError(s"parent: history does not contain parent ${block.header.reference}"))
          grandParent = blockchain.parentHeader(parent, 2)
          effectiveBalance <- genBalance(height, block.header.reference).left.map(GenericError(_))
          _                <- validateBlockVersion(height, block, blockchain)
          _                <- Either.cond(blockTime - currentTs < MaxTimeDrift, (), BlockFromFuture(blockTime, currentTs))
          // Skip PoS validation for PoW blocks (marked with rewardVote = -1)
          isPowBlock = block.header.rewardVote == -1L
          _                <- if (isPowBlock) Right(()) else pos.validateBaseTarget(height, block, parent, grandParent)
          hitSource        <- if (isPowBlock) Right(block.header.generationSignature) else pos.validateGenerationSignature(block)
          
          // PoW blocks: Validate difficulty and PoW solution (CONSENSUS CRITICAL!)
          _ <- if (isPowBlock) {
                 // 1. Calculate expected difficulty from blockchain state
                 val expectedDifficulty = com.wavesplatform.mining.DifficultyAdjustment.calculateDifficulty(
                   blockchain,
                   height + 1
                 )
                 
                 // 2. Extract difficulty from block (stored in baseTarget for PoW)
                 val blockDifficulty = block.header.baseTarget
                 
                 // 3. Validate difficulty matches consensus
                 if (blockDifficulty != expectedDifficulty) {
                   Left(GenericError(
                     f"PoW difficulty mismatch at height ${height + 1}: " +
                     f"expected 0x${expectedDifficulty}%08x, got 0x${blockDifficulty}%08x"
                   ))
                 } else {
                   // 4. Extract mutation vector (first 16 bytes of generationSignature)
                   val mutationVector = block.header.generationSignature.arr.take(16)
                   
                   // 5. Get parent block ID - use Waves block ID (matches template!)
                   // Template and submission both use blockchain.blockHeader(parent).id()
                   val parentBlockId = blockchain.blockHeader(height)
                     .map(_.id().arr.take(32))
                     .getOrElse(Array.fill(32)(0.toByte))
                   
                   // Get parent's stateHash for stateRoot field
                   val parentStateRoot = parent.stateHash
                     .map(_.arr.take(32))
                     .getOrElse(Array.fill(32)(0.toByte))
                   
                   val powHeader = _root_.consensus.BlockHeader(
                     version = 1,
                     parentId = parentBlockId,
                     stateRoot = parentStateRoot,
                     timestamp = block.header.timestamp,
                     difficultyBits = blockDifficulty,
                     nonce = 0L,
                     mutationVector = mutationVector
                   )
                   
                   // 6. Validate PoW solution
                   val isValid = pow.Pow.verifyPowFromBytes(
                     powHeader.bytes(),
                     blockDifficulty
                   ).getOrElse(false)
                   
                   if (!isValid) {
                     Left(GenericError(
                       f"PoW solution invalid at height ${height + 1}: " +
                       f"mutation vector ${mutationVector.map("%02x".format(_)).mkString} " +
                       f"does not meet difficulty 0x${blockDifficulty}%08x"
                     ))
                   } else {
                     // Success! Log validation
                     println(s"\n✓ PoW VALIDATED at height ${height + 1}:")
                     println(f"   Difficulty: 0x${expectedDifficulty}%08x (${com.wavesplatform.mining.DifficultyAdjustment.difficultyDescription(expectedDifficulty)})")
                     println(f"   MV: ${mutationVector.map("%02x".format(_)).mkString}")
                     println(s"   Solution meets difficulty requirement ✓")
                     Right(())
                   }
                 }
               } else {
                 pos
                   .validateBlockDelay(height, block.header, parent, effectiveBalance)
                   .orElse(checkExceptions(height, block))
               }
        } yield hitSource
      }
      .left
      .map {
        case GenericError(x) => GenericError(s"Block $block is invalid: $x")
        case x               => x
      }

  private def checkExceptions(height: Int, block: Block): Either[ValidationError, Unit] = {
    Either
      .cond(
        exceptions.contains((height, block.id())),
        (),
        GenericError(s"Block time ${block.header.timestamp} less than expected")
      )
  }

  private def validateBlockVersion(parentHeight: Int, block: Block, blockchain: Blockchain): Either[ValidationError, Unit] = {
    Either.cond(
      blockchain.blockVersionAt(parentHeight + 1) == block.header.version,
      (),
      GenericError(s"Block version should be equal to ${blockchain.blockVersionAt(parentHeight + 1)}")
    )
  }

  private def validateChallengedHeader(block: Block, blockchain: Blockchain): Either[ValidationError, Unit] =
    for {
      _ <- Either.cond(
        block.header.challengedHeader.isEmpty || blockchain.supportsLightNodeBlockFields(blockchain.height + 1),
        (),
        BlockAppendError("Challenged header is not supported yet", block)
      )
      _ <- Either.cond(
        !block.header.challengedHeader.map(_.generator).contains(block.header.generator),
        (),
        BlockAppendError("Challenged block generator and challenging block generator should not be equal", block)
      )
    } yield ()

  private def validateStateHash(block: Block, blockchain: Blockchain): Either[ValidationError, Unit] =
    Either.cond(
      block.header.stateHash.isEmpty || blockchain.supportsLightNodeBlockFields(blockchain.height + 1),
      (),
      BlockAppendError("Block state hash is not supported yet", block)
    )

  private object metrics {
    val blockConsensusValidation = Kamon.timer("block-appender.block-consensus-validation").withoutTags()
    val appendBlock              = Kamon.timer("block-appender.blockchain-append-block").withoutTags()
  }

}
