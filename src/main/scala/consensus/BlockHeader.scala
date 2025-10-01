package consensus

import java.nio.ByteBuffer
import pow.Pow

/**
 * プロトコルの BlockHeader（最終形式 — ハードフォーク対象）。
 *
 * ネットワーク全体で使用されるバイト順（コンセンサス上の決定事項）:
 *  - version（4 バイト、ビッグエンディアン）
 *  - parentId（32 バイト）
 *  - stateRoot（32 バイト）
 *  - timestamp（8 バイト、ビッグエンディアン）
 *  - difficultyBits（8 バイト、ビッグエンディアン）
 *  - nonce（8 バイト、ビッグエンディアン）
 *  - mutationVectorLength（4 バイト、ビッグエンディアン）
 *  - mutationVector（N バイト）
 */
case class BlockHeader(
  version: Int,
  parentId: Array[Byte],
  stateRoot: Array[Byte],
  timestamp: Long,
  difficultyBits: Long,
  nonce: Long,
  mutationVector: Array[Byte]
) {

  /** ヘッダーの完全なシリアライズ（ネットワーク、永続化、PoW で使用）。 */
  def bytes(): Array[Byte] = BlockHeader.serialize(this)

  /** Pow.verifyPowFromBytes を用いてヘッダーの PoW を検証します。 */
  def validatePow(): Boolean = {
    Pow.verifyPowFromBytes(bytes(), difficultyBits).getOrElse(false)
  }
}

object BlockHeader {

  def serialize(h: BlockHeader): Array[Byte] = {
    val mvLen = if (h.mutationVector != null) h.mutationVector.length else 0
    val total = 4 + 32 + 32 + 8 + 8 + 8 + 4 + mvLen
    val bb = ByteBuffer.allocate(total)
    bb.putInt(h.version)
    bb.put(fitToLength(h.parentId, 32))
    bb.put(fitToLength(h.stateRoot, 32))
    bb.putLong(h.timestamp)
    bb.putLong(h.difficultyBits)
    bb.putLong(h.nonce)
    bb.putInt(mvLen)
    if (mvLen > 0) bb.put(h.mutationVector)
    bb.array()
  }

  def deserialize(data: Array[Byte]): BlockHeader = {
    val bb = ByteBuffer.wrap(data)
    val version = bb.getInt()
    val parent = new Array[Byte](32); bb.get(parent)
    val state = new Array[Byte](32); bb.get(state)
    val timestamp = bb.getLong()
    val difficultyBits = bb.getLong()
    val nonce = bb.getLong()
    val mvLen = bb.getInt()
    if (mvLen < 0 || mvLen > bb.remaining()) throw new IllegalArgumentException("invalid mutationVector length")
    val mv = new Array[Byte](mvLen)
    if (mvLen > 0) bb.get(mv)
    BlockHeader(version, parent, state, timestamp, difficultyBits, nonce, mv)
  }

  private def fitToLength(arr: Array[Byte], len: Int): Array[Byte] = {
    if (arr == null) Array.fill(len)(0.toByte)
    else if (arr.length == len) arr
    else if (arr.length < len) {
      val out = Array.fill(len)(0.toByte)
      System.arraycopy(arr, 0, out, len - arr.length, arr.length)
      out
    } else {
      val out = new Array[Byte](len)
      System.arraycopy(arr, arr.length - len, out, 0, len)
      out
    }
  }
}
