// Akka-HTTP routes that expose header in hex and JSON.

package com.wavesplatform.api.http

import org.apache.pekko.http.scaladsl.server.Directives._
import org.apache.pekko.http.scaladsl.server.Route
import org.apache.pekko.http.scaladsl.model.StatusCodes
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import spray.json._
import spray.json.DefaultJsonProtocol._
import _root_.consensus.BlockHeader

case class BlockHeaderResponse(header_hex: String)
case class BlockHeaderPrefixResponse(header_prefix_hex: String)
case class MiningSubmission(height: Long, mutation_vector_hex: String, timestamp: Option[Long] = None)
case class MiningSubmissionResponse(success: Boolean, message: String, hash: Option[String] = None)
case class MiningTemplateResponse(height: Long, header_prefix_hex: String, difficulty_bits: String, target_hex: String, timestamp: Long)

trait BlockStorage {
  def getBlockHeaderByHeight(height: Long): Option[_root_.consensus.BlockHeader]
}

class BlockHeaderRoutes(
  blockStorage: BlockStorage,
  blockchainUpdater: com.wavesplatform.state.Blockchain,
  powBlockPersister: Option[PowBlockPersister] = None
) extends ApiRoute {
  import BlockHeaderRoutes._
  
  override val route: Route = 
    // POST endpoint to submit mined block
    (post & path("mining" / "submit")) {
      entity(as[MiningSubmission]) { submission =>
        complete {
          // For template-based mining, reconstruct header from parent block
          val parentHeight = submission.height - 1
          val parentBlockOpt = blockStorage.getBlockHeaderByHeight(parentHeight)
          
          parentBlockOpt match {
            case Some(parentBlock) =>
              // Parse mutation vector from hex
              val mvResult = try {
                Right(submission.mutation_vector_hex.grouped(2).map(Integer.parseInt(_, 16).toByte).toArray)
              } catch {
                case _: Exception =>
                  Left(StatusCodes.BadRequest -> MiningSubmissionResponse(
                    success = false,
                    message = "Invalid mutation vector hex format"
                  ))
              }
              
              mvResult match {
                case Left(error) => error
                case Right(mvBytes) =>
                  // Reconstruct the mined header from parent + mutation vector
                  // Calculate expected difficulty for this height
                  val expectedDifficulty = com.wavesplatform.mining.DifficultyAdjustment.calculateDifficulty(
                    blockchainUpdater,
                    submission.height.toInt
                  )
                  
                  // Get Waves parent block ID (same as template)
                  val wavesParentId = blockchainUpdater.blockHeader((submission.height - 1).toInt)
                    .map(_.id().arr.take(32))
                    .getOrElse(Array.fill(32)(0.toByte))
                  
                  // This should match the template we provided
                  val minedHeader = _root_.consensus.BlockHeader(
                    version = 1,
                    parentId = wavesParentId,  // Waves parent block ID
                    stateRoot = parentBlock.stateRoot,       // Inherit state root
                    timestamp = submission.timestamp.getOrElse(System.currentTimeMillis()),  // Use template timestamp if provided
                    difficultyBits = expectedDifficulty,    // Dynamic difficulty!
                    nonce = 0L,
                    mutationVector = mvBytes
                  )
                  
                  // Validate PoW
                  if (minedHeader.validatePow()) {
                    val headerHash = minedHeader.bytes().map("%02x".format(_)).mkString
                    val mvHex = mvBytes.map("%02x".format(_)).mkString
                    
                    // Log the valid solution
                    log.info(s"✅ Valid PoW solution found for block ${submission.height}!")
                    log.info(s"   Mutation Vector: $mvHex")
                    log.info(s"   Block Hash: ${headerHash.take(64)}...")
                    
                    // Persist block to blockchain if persister is available
                    powBlockPersister match {
                      case Some(persister) =>
                        log.info(s"   Attempting to persist block to blockchain...")
                        persister.persistPowBlock(minedHeader, submission.height) match {
                          case Right(blockId) =>
                            log.info(s"   ✅ Block successfully persisted! Block ID: ${blockId.take(16)}...")
                            MiningSubmissionResponse(
                              success = true,
                              message = "Valid PoW solution accepted and added to blockchain",
                              hash = Some(headerHash)
                            )
                          case Left(error) =>
                            log.error(s"   ❌ Failed to persist block: $error")
                            MiningSubmissionResponse(
                              success = false,
                              message = s"Valid PoW but failed to persist: ${error.toString}"
                            )
                        }
                      case None =>
                        log.warn(s"   ⚠️ No block persister configured - validation only")
                        MiningSubmissionResponse(
                          success = true,
                          message = "Valid PoW solution accepted (validation only - not persisted to blockchain yet)",
                          hash = Some(headerHash)
                        )
                    }
                  } else {
                    MiningSubmissionResponse(
                      success = false,
                      message = "Invalid PoW: solution does not meet difficulty target"
                    )
                  }
              }
            case None =>
              StatusCodes.NotFound -> MiningSubmissionResponse(
                success = false,
                message = s"Parent block at height $parentHeight not found. Cannot create block ${submission.height}"
              )
          }
        }
      }
    } ~ 
    // GET endpoint to create new PoW block template for mining
    (get & path("mining" / "template")) {
      complete {
        // Get the latest block from blockchain
        val currentHeight = blockStorage.getBlockHeaderByHeight(0) match {
          case Some(_) => 
            // Find highest valid block by trying heights
            var h = 1L
            while (h < 10000 && blockStorage.getBlockHeaderByHeight(h).isDefined) {
              h += 1
            }
            h - 1
          case None => 0L
        }
        
        val parentBlock = blockStorage.getBlockHeaderByHeight(currentHeight)
        
        parentBlock match {
          case Some(parent) =>
            // Create new PoW block template for height N+1
            val newHeight = currentHeight + 1
            val currentTime = System.currentTimeMillis()
            
            // Calculate dynamic difficulty based on recent block times
            val difficulty = com.wavesplatform.mining.DifficultyAdjustment.calculateDifficulty(
              blockchainUpdater,
              newHeight.toInt
            )
            
            // Get Waves parent block ID (NOT consensus bytes!)
            val wavesParentId = blockchainUpdater.blockHeader(currentHeight.toInt)
              .map(_.id().arr.take(32))
              .getOrElse(Array.fill(32)(0.toByte))
            
            // Build template header (without mutation vector)
            val template = _root_.consensus.BlockHeader(
              version = 1,
              parentId = wavesParentId,  // Use Waves block ID for consistency
              stateRoot = parent.stateRoot,       // Inherit state root  
              timestamp = currentTime,
              difficultyBits = difficulty,        // Dynamic difficulty!
              nonce = 0L,
              mutationVector = Array.fill(16)(0.toByte) // Placeholder
            )
            
            // Serialize prefix (without mutation vector)
            val fullBytes = template.bytes()
            val prefixBytes = fullBytes.take(fullBytes.length - 16) // Remove 16-byte MV
            
            // Calculate 32-byte big-endian target from difficulty bits
            val target = pow.Pow.targetFromBits(difficulty)
            val targetBytes = target.toByteArray
            
            // Ensure exactly 32 bytes, pad with zeros if needed  
            val target32Bytes = if (targetBytes.length < 32) {
              Array.fill(32 - targetBytes.length)(0.toByte) ++ targetBytes
            } else if (targetBytes.length > 32) {
              targetBytes.takeRight(32)
            } else {
              targetBytes
            }
            val targetHex = target32Bytes.map("%02x".format(_)).mkString
            
            log.info(s"📋 Created mining template for height $newHeight")
            log.info(s"   Parent: ${parent.bytes().take(32).map("%02x".format(_)).mkString.take(16)}...")
            log.info(s"   Timestamp: $currentTime")
            log.info(s"   Difficulty: ${com.wavesplatform.mining.DifficultyAdjustment.difficultyDescription(difficulty)}")
            log.info(s"   Target: ${targetHex.take(16)}...")
            
            MiningTemplateResponse(
              height = newHeight,
              header_prefix_hex = prefixBytes.map("%02x".format(_)).mkString,
              difficulty_bits = f"${difficulty}%08x",  // Dynamic difficulty as hex
              target_hex = targetHex,  // 32-byte big-endian target
              timestamp = currentTime
            )
          case None =>
            StatusCodes.InternalServerError -> "Unable to fetch parent block for template"
        }
      }
    } ~ 
    // GET endpoint to fetch header for mining
    (get & path("block" / LongNumber / "headerHex")) { height =>
    complete {
      blockStorage.getBlockHeaderByHeight(height) match {
        case Some(header) =>
          val headerBytes = header.bytes()
          val prefixBytes = headerBytes.take(headerBytes.length - header.mutationVector.length)
          BlockHeaderPrefixResponse(prefixBytes.map("%02x".format(_)).mkString)
        case None =>
          StatusCodes.NotFound -> s"Block at height $height not found"
      }
    }
  } ~ (get & path("block" / LongNumber / "headerJson")) { height =>
    complete {
      blockStorage.getBlockHeaderByHeight(height) match {
        case Some(header) =>
          val json = s"""
            |{
            |  "version": ${header.version},
            |  "parentId": "${header.parentId.map("%02x".format(_)).mkString}",
            |  "stateRoot": "${header.stateRoot.map("%02x".format(_)).mkString}",
            |  "timestamp": ${header.timestamp},
            |  "difficultyBits": "${header.difficultyBits.toHexString}",
            |  "nonce": ${header.nonce},
            |  "mutationVector": "${header.mutationVector.map("%02x".format(_)).mkString}"
            |}
          """.stripMargin
          json
        case None => StatusCodes.NotFound -> s"Block at height $height not found"
      }
    }
  } ~ (get & path("block" / LongNumber / "headerRawHex")) { height =>
    complete {
      blockStorage.getBlockHeaderByHeight(height) match {
        case Some(header) =>
          BlockHeaderResponse(header.bytes().map("%02x".format(_)).mkString)
        case None =>
          StatusCodes.NotFound -> s"Block at height $height not found"
      }
    }
  }
}

object BlockHeaderRoutes {
  implicit val blockHeaderResponseFormat: RootJsonFormat[BlockHeaderResponse] = jsonFormat1(BlockHeaderResponse.apply)
  implicit val blockHeaderPrefixResponseFormat: RootJsonFormat[BlockHeaderPrefixResponse] = jsonFormat1(BlockHeaderPrefixResponse.apply)
  implicit val miningSubmissionFormat: RootJsonFormat[MiningSubmission] = jsonFormat3(MiningSubmission.apply)
  implicit val miningSubmissionResponseFormat: RootJsonFormat[MiningSubmissionResponse] = jsonFormat3(MiningSubmissionResponse.apply)
  implicit val miningTemplateResponseFormat: RootJsonFormat[MiningTemplateResponse] = jsonFormat5(MiningTemplateResponse.apply)
}
