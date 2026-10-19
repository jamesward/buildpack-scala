# AGENTS.md: buildpack-scala

Classic Heroku buildpack (bash) for Scala apps built with sbt 2 and sbt-native-packager's `JavaAppPackaging`: runs `./sbt stage` and ships `universal/stage` as the slug, chained after `heroku/jvm`. Used in production by every factory Scala server on Heroku (javadocs, webjars, webjars-file-service, the mytoolbook apps, skillsjars, jev-llm-c4, json-paste, hello-zio-http). It also adds `-XX:+ExitOnOutOfMemoryError` to `JAVA_TOOL_OPTIONS` (see README).

## Skills

Follow the `zen-of-projects` Skill (its "Heroku Buildpack Projects" section); this file records only project facts and exceptions. For design and testing strategy, follow `zen-of-james`. There's no Skills dependency (bash has no SkillsJars): `.factory/MAINTENANCE.md` reads the Skills from a clone of https://github.com/jamesward/skills.

## MCP

None.

## Build & test

Full validation (CI runs the same):

```bash
shellcheck -x --severity=warning bin/detect bin/compile bin/release bin/test bin/test-compile bin/util/sbt-env.sh test/*.sh
./test/smoke-subproject.sh
./test/smoke-sbta.sh
SAMPLE_APP=$PWD/test/fixtures/sample-app ./test/smoke.sh && SAMPLE_APP=$PWD/test/fixtures/sample-app ./test/ci-smoke.sh
```

The end-to-end smoke tests need a JDK and sbt on `PATH` (the fixture's `./sbt` calls the system `sbt`).

## Production

Every push to `main` is what all those apps build with on their next deploy. Changes under `bin/` need a human (`needs-human`); CI, test, fixture and doc changes follow the normal merge policy.

## Maintenance routine

`.factory/MAINTENANCE.md` (weekly), following the `zen-of-projects` Skill.
