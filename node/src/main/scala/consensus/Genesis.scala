package consensus

import java.security.MessageDigest

object Genesis {

  // コインベース/ジェネシス用の任意テキスト（プロジェクトに合わせて変更可）
  val GenesisMessage: String = "Waves Pow hard fork genesis block - Sep 2025"

  // ジェネシスブロックのヘッダー（mutationVector を含む）
  lazy val Block: BlockHeader = {
    val parentId = Array.fill(32)(0.toByte)
    val stateRoot = sha256(GenesisMessage.getBytes("UTF-8"))

    BlockHeader(
      version = 1,
      parentId = parentId,
      stateRoot = stateRoot,
      timestamp = 1726365600L, // 例: 2025-09-29 (UTC)
      difficultyBits = 0x1f00ffffL,
      nonce = 0L,
      mutationVector = Array.fill(16)(0x00.toByte) // 16バイトの初期値でより現実的なマイニング
    )
  }

  private def sha256(bytes: Array[Byte]): Array[Byte] = {
    val d = MessageDigest.getInstance("SHA-256")
    d.digest(bytes)
  }
}

object PrintGenesis extends App {
  val g = Genesis.Block
  println(s"Genesis header bytes (hex): ${g.bytes().map(b => f"$b%02x").mkString}")
  println(s"Valid POW? ${g.validatePow()}")
}
