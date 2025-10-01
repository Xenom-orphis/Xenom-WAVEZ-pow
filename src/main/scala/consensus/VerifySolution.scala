package consensus

import pow.Pow

object VerifySolution {
  def main(args: Array[String]): Unit = {
    def usage(): Unit = {
      Console.err.println("Usage: VerifySolution <headerPrefixHex> <mvHex> <bitsHex>")
      sys.exit(1)
    }

    if (args.length < 3) usage()

    val headerPrefixHex = args(0).trim
    val mvHex           = args(1).trim
    val bitsHex         = args(2).trim

    def hexToBytes(s: String): Array[Byte] = {
      val clean = s.replaceAll("\\s+", "")
      if (!clean.matches("[0-9a-fA-F]+") || (clean.length % 2 != 0))
        throw new IllegalArgumentException("Invalid hex input")
      clean.grouped(2).map(Integer.parseInt(_, 16).toByte).toArray
    }

    val prefix = hexToBytes(headerPrefixHex)
    val mv     = hexToBytes(mvHex)
    val fullHeaderBytes = prefix ++ mv
    val bits = java.lang.Long.parseLong(bitsHex, 16)

    val result = Pow.verifyPowFromBytes(fullHeaderBytes, bits).getOrElse(false)
    println(s"verifyPowFromBytes => ${result}")
  }
}
