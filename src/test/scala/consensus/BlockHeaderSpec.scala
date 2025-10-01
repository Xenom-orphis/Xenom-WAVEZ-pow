package consensus

import org.scalatest.funsuite.AnyFunSuite

class BlockHeaderSpec extends AnyFunSuite {
  test("serialize-deserialize roundtrip") {
    val header = BlockHeader(
      version = 1,
      parentId = Array.fill(32)(1.toByte),
      stateRoot = Array.fill(32)(2.toByte),
      timestamp = 1L,
      difficultyBits = 0x1f00ffffL,
      nonce = 0L,
      mutationVector = Array.fill(16)(3.toByte)
    )
    val bytes = header.bytes()
    val parsed = BlockHeader.deserialize(bytes)
    assert(parsed.version == header.version)
    assert(parsed.mutationVector.sameElements(header.mutationVector))
  }
}
