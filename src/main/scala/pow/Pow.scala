package pow

import java.nio.ByteBuffer
import scala.util.Try

// BLAKE3 via Apache Commons Codec  
import org.apache.commons.codec.digest.Blake3

// 最小限の BlockHeader 表現 — プロジェクトの BlockHeader を置き換えてください
case class BlockHeader(
  version: Int,
  prevHash: Array[Byte],
  merkleRoot: Array[Byte],
  timestamp: Long,
  bits: Long // 難易度コンパクト/ターゲット (適応する形式に変更)
)

object Pow {
  def serializeHeaderForPow(header: BlockHeader, mutationVector: Array[Byte]): Array[Byte] = {
    val bb = ByteBuffer.allocate(4 + header.prevHash.length + header.merkleRoot.length + 8 + mutationVector.length)
    bb.putInt(header.version)
    bb.put(header.prevHash)
    bb.put(header.merkleRoot)
    bb.putLong(header.timestamp)
    bb.put(mutationVector)
    bb.array()
  }

  def hashToBigInt(hash: Array[Byte]): BigInt = BigInt(1, hash)

  /**
   * 圧縮形式の 'bits' (uint32) を target (BigInt) に変換します。
   * 実装は Bitcoin で使用されているコンパクト形式に基づきます:
   * - 1 バイトの指数 (E)
   * - 3 バイトの係数 (C)（ビッグエンディアン）
   * bits = (E << 24) | C
   * target = C * 256^(E-3)
   *
   * ここでは、符号なし 32 ビット値の読み取り時の問題を避けるために Long を受け取ります。
   */
  def targetFromBits(bits: Long): BigInt = {
    val unsignedBits = bits & 0xffffffffL
    val exponent = ((unsignedBits >>> 24) & 0xff).toInt
    val coefficient = unsignedBits & 0x00ffffffL

    val coeffBig = BigInt(coefficient)
    val exp = exponent - 3
    if (exp >= 0) coeffBig * (BigInt(256).pow(exp)) else coeffBig / (BigInt(256).pow(-exp))
  }

  def verifyPow(header: BlockHeader, mutationVector: Array[Byte], bits: Long): Try[Boolean] = Try {
    val data = serializeHeaderForPow(header, mutationVector)

    val hasher = Blake3.initHash()
    hasher.update(data)
    val digest = new Array[Byte](32)
    hasher.doFinalize(digest)

    val hInt = hashToBigInt(digest)
    val target = targetFromBits(bits)
    hInt <= target
  }

  /**
   * Verifica o PoW hashando diretamente os bytes do cabeçalho serializado e
   * comparando com o target derivado de 'bits'.
   */
  def verifyPowFromBytes(headerBytes: Array[Byte], bits: Long): Try[Boolean] = Try {
    val hasher = Blake3.initHash()
    hasher.update(headerBytes)
    val digest = new Array[Byte](32)
    hasher.doFinalize(digest)

    val hInt = hashToBigInt(digest)
    val target = targetFromBits(bits)
    hInt <= target
  }
}

object PowTest extends App {
  val header = BlockHeader(1, Array.fill(32)(0.toByte), Array.fill(32)(1.toByte), System.currentTimeMillis() / 1000L, 0L)
  val mutation = Array.fill(16)(0.toByte)

  Pow.verifyPow(header, mutation, 0L).fold(
    err => println(s"Erro ao verificar PoW: ${err.getMessage}"),
    ok  => println(s"PoW válido? $ok")
  )
}
