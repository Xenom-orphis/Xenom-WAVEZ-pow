package com.wavesplatform.network

import com.wavesplatform.block.Block
import com.wavesplatform.history.History
import com.wavesplatform.settings.SynchronizationSettings
import com.wavesplatform.utils.ScorexLogging
import io.netty.channel.ChannelHandler.Sharable
import io.netty.channel.{ChannelHandlerContext, ChannelInboundHandlerAdapter}

import scala.concurrent.{ExecutionContext, Future}
import scala.util.{Failure, Success}

@Sharable
class HistoryReplierL1(score: => BigInt, history: History, settings: SynchronizationSettings)(implicit ec: ExecutionContext)
    extends ChannelInboundHandlerAdapter
    with ScorexLogging {

  private def respondWith(ctx: ChannelHandlerContext, value: Future[Message]): Unit =
    value.onComplete {
      case Failure(e) => log.debug(s"${id(ctx)} Error processing request", e)
      case Success(value) =>
        if (ctx.channel().isOpen) {
          ctx.writeAndFlush(value)
        } else {
          log.trace(s"${id(ctx)} Channel is closed")
        }
    }

  override def channelRead(ctx: ChannelHandlerContext, msg: AnyRef): Unit = msg match {
    case GetSignatures(otherSigs) =>
      println(s"📥 [MAIN] Received GetSignatures from ${ctx.channel().remoteAddress()}, known sigs: ${otherSigs.size}")
      val blockIds = history.blockIdsAfter(otherSigs, settings.maxRollback)
      println(s"📤 [MAIN] Responding with ${blockIds.size} block IDs")
      respondWith(ctx, Future(Signatures(blockIds)))

    case GetBlock(sig) =>
      println(s"📥 [MAIN] Received GetBlock request from ${ctx.channel().remoteAddress()} for block ${sig}")
      respondWith(
        ctx,
        Future(history.loadBlockBytes(sig))
          .map {
            case Some((blockVersion, bytes)) =>
              println(s"📤 [MAIN] Sending block ${sig} (version $blockVersion, ${bytes.length} bytes)")
              RawBytes(if (blockVersion < Block.ProtoBlockVersion) BlockSpec.messageCode else PBBlockSpec.messageCode, bytes)
            case _ => 
              println(s"❌ [MAIN] Block ${sig} not found in history!")
              throw new NoSuchElementException(s"Error loading block $sig")
          }
      )

    case MicroBlockRequest(microBlockId) =>
      respondWith(
        ctx,
        Future(history.loadMicroBlock(microBlockId)).map {
          case Some(microBlock) => RawBytes.fromMicroBlock(MicroBlockResponse(microBlock, microBlockId))
          case _                => throw new NoSuchElementException(s"Error loading microblock $microBlockId")
        }
      )

    case GetSnapshot(id) =>
      respondWith(
        ctx,
        Future(history.loadBlockSnapshots(id)).map {
          case Some(snapshots) => BlockSnapshotResponse(id, snapshots)
          case _               => throw new NoSuchElementException(s"Error loading snapshots for block $id")
        }
      )

    case MicroSnapshotRequest(id) =>
      respondWith(
        ctx,
        Future(history.loadMicroBlockSnapshots(id)).map {
          case Some(snapshots) => MicroBlockSnapshotResponse(id, snapshots)
          case _               => throw new NoSuchElementException(s"Error loading snapshots for microblock $id")
        }
      )

    case _: Handshake =>
      respondWith(ctx, Future(LocalScoreChanged(score)))

    case _ => super.channelRead(ctx, msg)
  }

  def cacheSizes: HistoryReplierL1.CacheSizes = HistoryReplierL1.CacheSizes(0, 0)
}

object HistoryReplierL1 {
  case class CacheSizes(blocks: Long, microBlocks: Long)
}
