package consensus

object PrintHeaderPrefix extends App {
  val h = Genesis.Block
  val full = h.bytes()
  val mvLen = if (h.mutationVector != null) h.mutationVector.length else 0
  val prefix = if (mvLen == 0) full else full.dropRight(mvLen)
  val prefixHex = prefix.map(b => f"${b & 0xff}%02x").mkString
  println(prefixHex)
}
