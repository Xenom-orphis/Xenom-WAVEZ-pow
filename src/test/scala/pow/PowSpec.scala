package pow

import org.scalatest.funsuite.AnyFunSuite

class PowSpec extends AnyFunSuite {
  test("verifyPow should run without errors") {
    val header = BlockHeader(1, Array.fill(32)(0.toByte), Array.fill(32)(1.toByte), System.currentTimeMillis() / 1000L, 0L)
    val mutation = Array.fill(16)(0.toByte)
    val result = Pow.verifyPow(header, mutation, 0x207fffffL)
    assert(result.isSuccess)
  }
}
