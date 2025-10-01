/* IDEA notes
 * May require to delete .idea and re-import with all checkboxes
 * Worksheets may not work: https://youtrack.jetbrains.com/issue/SCL-6726
 * To work with worksheets, make sure:
   1. You've selected the appropriate project
   2. You've checked "Make project before run"
 */

Global / onChangedBuildSource := ReloadOnSourceChanges

enablePlugins(GitVersioning)

git.uncommittedSignifier       := Some("DIRTY")
ThisBuild / git.useGitDescribe := true
ThisBuild / PB.protocVersion   := "4.31.1"

ThisBuild / dependencyOverrides ++= Dependencies.overrides.value

lazy val lang =
  crossProject(JSPlatform, JVMPlatform)
    .withoutSuffixFor(JVMPlatform)
    .crossType(CrossType.Full)
    .settings(
      assembly / test := {},
      libraryDependencies ++= Dependencies.lang.value ++ Dependencies.test,
      inConfig(Compile)(
        Seq(
          sourceGenerators += Tasks.docSource,
          PB.targets += scalapb.gen(flatPackage = true) -> sourceManaged.value,
          PB.protoSources += PB.externalIncludePath.value,
          PB.generate / includeFilter := { (f: File) =>
            (** / "waves" / "lang" / "*.proto").matches(f.toPath)
          },
          PB.deleteTargetDirectory := false
        )
      )
    )

lazy val `lang-jvm` = lang.jvm
  .enablePlugins(PublishedModule)
  .settings(
    name                                  := "RIDE Compiler",
    normalizedName                        := "lang",
    description                           := "The RIDE smart contract language compiler",
    libraryDependencies += "org.scala-js" %% "scalajs-stubs" % "1.1.0" % Provided
  )

lazy val `lang-js` = lang.js
  .enablePlugins(VersionObject)

lazy val `lang-testkit` = project
  .in(file("lang/testkit"))
  .dependsOn(`lang-jvm`)
  .enablePlugins(PublishedModule)
  .settings(
    libraryDependencies ++=
      Dependencies.test.map(_.withConfigurations(Some("compile"))) ++ Dependencies.qaseReportDeps ++ Dependencies.logDeps ++ Seq(
        "com.typesafe.scala-logging" %% "scala-logging" % "3.9.5"
      )
  )

lazy val `lang-tests` = project
  .in(file("lang/tests"))
  .dependsOn(`lang-testkit`)

lazy val `lang-tests-js` = project
  .in(file("lang/tests-js"))
  .enablePlugins(ScalaJSPlugin)
  .dependsOn(`lang-js`)
  .settings(
    libraryDependencies += Dependencies.scalaJsTest.value,
    testFrameworks += new TestFramework("utest.runner.Framework")
  )

lazy val node = project.dependsOn(`lang-jvm`)

lazy val `node-testkit` = project
  .in(file("node/testkit"))
  .dependsOn(`node`, `lang-testkit`)
  .enablePlugins(PublishedModule)
  .settings(libraryDependencies ++= Dependencies.nodeTests)

lazy val `node-tests` = project
  .in(file("node/tests"))
  .dependsOn(`node-testkit`)
  .settings(libraryDependencies ++= Dependencies.logDeps)

lazy val `grpc-server` =
  project.dependsOn(node % "compile;runtime->provided", `node-testkit`)

lazy val `ride-runner` = project.dependsOn(node, `grpc-server`, `node-testkit`)
lazy val `node-it`     = project.dependsOn(`repl-jvm`, `grpc-server`, `node-testkit`)

lazy val `node-generator` = project.dependsOn(node, `node-testkit`)

lazy val benchmark = project.dependsOn(node, `node-testkit`)

lazy val repl = crossProject(JSPlatform, JVMPlatform)
  .withoutSuffixFor(JVMPlatform)
  .crossType(CrossType.Full)
  .settings(
    libraryDependencies ++=
      Dependencies.protobuf.value ++
        Dependencies.circe.value,
    inConfig(Compile)(
      Seq(
        PB.targets += scalapb.gen(flatPackage = true) -> sourceManaged.value,
        PB.protoSources += PB.externalIncludePath.value,
        PB.generate / includeFilter := { (f: File) =>
          (** / "waves" / "*.proto").matches(f.toPath)
        }
      )
    )
  )

lazy val `repl-jvm` = repl.jvm
  .dependsOn(`lang-jvm`, `lang-testkit`)
  .settings(
    libraryDependencies ++= Dependencies.circe.value ++ Seq(
      "org.scala-js" %% "scalajs-stubs" % "1.1.0" % Provided,
      Dependencies.sttp3
    )
  )

lazy val `repl-js` = repl.js
  .dependsOn(`lang-js`)
  .settings(
    libraryDependencies += "org.scala-js" %%% "scala-js-macrotask-executor" % "1.1.1"
  )

lazy val `curve25519-test` = project.dependsOn(node)

lazy val `waves-node` = (project in file("."))
  .aggregate(
    `lang-js`,
    `lang-jvm`,
    `lang-tests`,
    `lang-tests-js`,
    `lang-testkit`,
    `repl-js`,
    `repl-jvm`,
    node,
    `node-it`,
    `node-testkit`,
    `node-tests`,
    `node-generator`,
    `grpc-server`,
    benchmark,
    `ride-runner`
  )

inScope(Global)(
  Seq(
    scalaVersion         := "3.7.2",
    organization         := "com.wavesplatform",
    organizationName     := "Waves Platform",
    organizationHomepage := Some(url("https://wavesplatform.com")),
    licenses             := Seq(("MIT", url("https://github.com/wavesplatform/Waves/blob/master/LICENSE"))),
    publish / skip       := true,
    scalacOptions ++= Seq(
      "-feature",
      "-deprecation",
      "-unchecked",
      "-language:higherKinds",
      "-language:implicitConversions",
      "-language:postfixOps",
      "-Wunused:all",
      "-Wconf:cat=deprecation&origin=com.wavesplatform.api.grpc.*:s",                                // Ignore gRPC warnings
      "-Wconf:cat=deprecation&origin=com.wavesplatform.protobuf.transaction.InvokeScriptResult.*:s", // Ignore deprecated argsBytes
      "-Wconf:cat=deprecation&origin=com.wavesplatform.state.InvokeScriptResult.*:s",
      "-Wconf:cat=deprecation&origin=com\\.wavesplatform\\.(lang\\..*|JsApiUtils)&origin=com\\.wavesplatform\\.lang\\.v1\\.compiler\\.Terms\\.LET_BLOCK:s",
      "-Wconf:src=src_managed/.*:s"
    ),
    libraryDependencies ++= Seq(
      // BLAKE3 via Apache Commons Codec (publicado no Maven Central)
      "commons-codec" % "commons-codec" % "1.19.0",

      // Biblioteca de algoritmos genéticos (usada apenas no miner, não no validador)
      "io.jenetics" % "jenetics" % "7.2.0",

      // Test framework for root-level tests
      "org.scalatest" %% "scalatest" % "3.2.19" % Test,

      // HTTP & JSON for routes/CLI (Apache Pekko - Scala 3 compatible)
      "org.apache.pekko" %% "pekko-http" % "1.1.0",
      "org.apache.pekko" %% "pekko-http-spray-json" % "1.1.0",
      "org.apache.pekko" %% "pekko-stream" % "1.1.0",
      "com.typesafe.play" %% "play-json" % "2.10.6",
      "com.softwaremill.sttp.client3" %% "core" % "3.9.6"
    ),
    crossPaths        := false,
    cancelable        := true,
    parallelExecution := true,
    /* http://www.scalatest.org/user_guide/using_the_runner
     * o - select the standard output reporter
     * I - show reminder of failed and canceled tests without stack traces
     * D - show all durations
     * O - drop InfoProvided events
     * F - show full stack traces
     * u - select the JUnit XML reporter with output directory
     */
    testOptions += Tests.Argument("-oIDOF", "-u", "target/test-reports"),
    testOptions += Tests.Setup(_ => sys.props("sbt-testing") = "true"),
    network         := Network.default(),
    instrumentation := false,
    resolvers ++= Resolver.sonatypeCentralSnapshots +: Seq(Resolver.mavenLocal),
    Compile / packageDoc / publishArtifact := false,
    concurrentRestrictions                 := Seq(Tags.limit(Tags.Test, math.min(EvaluateTask.SystemProcessors, 8))),
    // Resolve common assembly merge conflicts
    ThisBuild / assemblyMergeStrategy := {
      case PathList("META-INF", "MANIFEST.MF")                 => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "INDEX.LIST")                  => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", f) if f.endsWith(".SF")        => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", f) if f.endsWith(".DSA")       => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", f) if f.endsWith(".RSA")       => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "BC2048KE.SF")                 => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "BC2048KE.DSA")                => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "DUMMY.SF")                    => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "DUMMY.DSA")                   => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", xs @ _*) if xs.nonEmpty && xs.head == "versions" => sbtassembly.MergeStrategy.first
      case PathList("META-INF", "DEPENDENCIES")                 => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "NOTICE")                       => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "LICENSE")                      => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "license")                      => sbtassembly.MergeStrategy.discard
      case PathList("META-INF", "services", xs @ _*)            => sbtassembly.MergeStrategy.concat
      case PathList("reference.conf")                            => sbtassembly.MergeStrategy.concat
      case PathList("application.conf")                          => sbtassembly.MergeStrategy.concat
      case x if x.endsWith("module-info.class")                  => sbtassembly.MergeStrategy.discard
      case x if x.endsWith(".proto")                             => sbtassembly.MergeStrategy.first
      case x if x.endsWith(".properties")                        => sbtassembly.MergeStrategy.first
      case x if x.endsWith(".txt")                               => sbtassembly.MergeStrategy.first
      case x if x.endsWith("pom.properties")                     => sbtassembly.MergeStrategy.discard
      case x if x.endsWith("pom.xml")                            => sbtassembly.MergeStrategy.discard
      case _                                                      => sbtassembly.MergeStrategy.first
    },

    excludeLintKeys ++= Set(
      node / Universal / configuration,
      node / Linux / configuration,
      node / Debian / configuration,
      Global / maxParallelSuites
    )
  )
)

lazy val packageAll = taskKey[Unit]("Package all artifacts")
packageAll := {
  (node / assembly).value
  (`ride-runner` / assembly).value
  buildDebPackages.value
  buildTarballsForDocker.value
}

lazy val buildTarballsForDocker = taskKey[Unit]("Package node and grpc-server tarballs and copy them to docker/target")
buildTarballsForDocker := {
  IO.copyFile(
    (node / Universal / packageZipTarball).value,
    baseDirectory.value / "docker" / "target" / "waves.tgz"
  )
  IO.copyFile(
    (`grpc-server` / Universal / packageZipTarball).value,
    baseDirectory.value / "docker" / "target" / "waves-grpc-server.tgz"
  )
}

lazy val buildRIDERunnerForDocker = taskKey[Unit]("Package RIDE Runner tarball and copy it to docker/target")
buildRIDERunnerForDocker := {
  IO.copyFile(
    (`ride-runner` / Universal / packageZipTarball).value,
    (`ride-runner` / baseDirectory).value / "docker" / "target" / s"${(`ride-runner` / name).value}.tgz"
  )
}

lazy val checkPRRaw = taskKey[Unit]("Build a project and run unit tests")
checkPRRaw := Def
  .sequential(
    `waves-node` / clean,
    Def.task {
      (`lang-tests` / Test / test).value
      (`repl-jvm` / Test / test).value
      (`lang-js` / Compile / fastOptJS).value
      (`lang-tests-js` / Test / test).value
      (`grpc-server` / Test / test).value
      (`node-tests` / Test / test).value
      (`repl-js` / Compile / fastOptJS).value
      (`node-it` / Test / compile).value
      (benchmark / Test / compile).value
      (`node-generator` / Compile / compile).value
      (`ride-runner` / Test / test).value
    }
  )
  .value

def checkPR: Command = Command.command("checkPR") { state =>
  val newState = Project
    .extract(state)
    .appendWithoutSession(
      Seq(Global / scalacOptions ++= Seq("-Xfatal-warnings")),
      state
    )
  Project.extract(newState).runTask(checkPRRaw, newState)
  state
}

lazy val completeQaseRun = taskKey[Unit]("Complete Qase run")
completeQaseRun := Def.task {
  (`lang-testkit` / Test / runMain).toTask(" com.wavesplatform.report.QaseRunCompleter").value
}.value

lazy val buildDebPackages = taskKey[Unit]("Build DEB packages")
buildDebPackages := {
  (`grpc-server` / Debian / packageBin).value
  (node / Debian / packageBin).value
}

lazy val buildPlatformIndependentArtifacts = taskKey[Unit]("Build fat JARs for node and ride-runner and TGZ for grpc-server")
buildPlatformIndependentArtifacts := {
  (node / assembly).value
  (`ride-runner` / assembly).value
  (`grpc-server` / Universal / packageZipTarball).value
}

lazy val buildReleaseArtifacts: Command = Command("buildReleaseArtifacts")(_ => Network.networkParser) { (state, args) =>
  args.toSet[Network].foreach { n =>
    val newState = Project
      .extract(state)
      .appendWithoutSession(
        Seq(Global / network := n),
        state
      )
    Project.extract(newState).runTask(buildDebPackages, newState)
  }

  Project.extract(state).runTask(buildPlatformIndependentArtifacts, state)

  state
}

commands ++= Seq(checkPR, buildReleaseArtifacts)
