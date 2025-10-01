// Simple CLI that queries the node endpoint and prints headerPrefixHex for use with miner.

package cli

import sttp.client3._
import play.api.libs.json._

object HeaderPrefixCli {
  def main(args: Array[String]): Unit = {
    if (args.length < 2) {
    println("Usage: HeaderPrefixCli <nodeUrl> <height>")
    println("Example: HeaderPrefixCli http://127.0.0.1:36669 0")
    sys.exit(1)
    }

    val nodeUrl = args(0).stripSuffix("/")
    val height = args(1)

    val backend = HttpURLConnectionBackend()
    val request = basicRequest.get(uri"${nodeUrl}/block/${height}/headerRawHex")
    val response = request.send(backend)

    if (response.code.isSuccess) {
      val body = response.body.getOrElse("")
      val js = Json.parse(body)
      val headerHex = (js \ "header_hex").asOpt[String].getOrElse(throw new RuntimeException("header_hex not present"))
      // Deserialize to bytes to compute prefix length safely (we need mutationVector length). We'll call headerJson to get mv length.
      val jsonHeaderReq = basicRequest.get(uri"${nodeUrl}/block/${height}/headerJson").send(backend)
      if (jsonHeaderReq.code.isSuccess) {
        val headerJson = Json.parse(jsonHeaderReq.body.getOrElse("{}"))
        val mvHex = (headerJson \ "mutationVector").asOpt[String].getOrElse("")
        val mvLen = if (mvHex.isEmpty) 0 else mvHex.length / 2
        val fullBytes = headerHex.grouped(2).map(Integer.parseInt(_,16).toByte).toArray
        val prefix = if (mvLen == 0) fullBytes else fullBytes.dropRight(mvLen)
        val prefixHex = prefix.map(b => f"${b & 0xff}%02x").mkString
        println(prefixHex)
      } else {
        System.err.println(s"Failed to obtain headerJson: ${jsonHeaderReq.code}")
        sys.exit(2)
      }

    } else {
      System.err.println(s"Failed to obtain header: ${response.code} ${response.body}")
      sys.exit(2)
    }
  }
}

/*
Notes:
- Requires dependencies: sttp.client3, play-json (or you can use spray-json). Add to build.sbt:
  "com.softwaremill.sttp.client3" %% "core" % "3.8.3",
  "com.typesafe.play" %% "play-json" % "2.9.4"
- Compile and run with sbt, or build a fat jar.
- The CLI first requests headerRawHex to get the full bytes, then requests headerJson to get mutationVector length.
  This ensures correct extraction of prefix even if mutationVector has variable length.
*/
