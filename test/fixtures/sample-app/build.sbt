// Minimal sbt-native-packager app used by the buildpack's smoke tests.
// Kept deliberately tiny so CI exercises the real compile/stage path without
// pulling a large dependency tree.
name         := "sample-app"
scalaVersion := "3.3.4"

enablePlugins(JavaAppPackaging)

Compile / mainClass := Some("Main")
