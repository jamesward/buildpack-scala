// Minimal sbt-native-image app used by the buildpack's native image smoke test.
name         := "native-app"
scalaVersion := "3.10.1"

enablePlugins(NativeImagePlugin)

// GraalVM Community through the plugin's Coursier, with its download URL
// pinned (the plugin's Coursier 2.0.3 can't read the current Coursier JVM index).
nativeImageJvm      := "graalvm-community"
nativeImageVersion  := "25.6.5.1"
nativeImageJvmIndex := (baseDirectory.value / "project" / "graalvm-jvm-index.json").toURI.toString

Compile / mainClass := Some("Main")
