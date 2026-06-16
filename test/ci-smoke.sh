#!/usr/bin/env bash
# Smoke-test the Heroku CI / testpack flow (bin/test-compile + bin/test).
#
# This emulates a Heroku CI run:
#   * stage the app in a fresh BUILD_DIR
#   * inject a passing munit test (the sample app has none of its own)
#   * run bin/test-compile against BUILD_DIR + a temp CACHE_DIR
#   * verify that BUILD_DIR still contains the source tree (not destroyed,
#     unlike bin/compile's behaviour)
#   * verify that the in-slug sbt cache exists in BUILD_DIR/.heroku-sbt-cache
#   * run bin/test against the same BUILD_DIR with NO CACHE_DIR (to mimic
#     what Heroku does in test dynos), and verify exit 0
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
buildpack=$(cd "$here/.." && pwd)
src=${SAMPLE_APP:-$HOME/projects/hello/hello-zio-http}

[[ -d $src ]] || { echo "sample app not found: $src" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
build="$work/build"
cache="$work/cache"
env_dir="$work/env"
mkdir -p "$build" "$cache" "$env_dir"

echo "-----> Staging $src into $build"
tar -C "$src" -cf - \
  --exclude='./.git' \
  --exclude='./.idea' \
  --exclude='./.bsp' \
  --exclude='./target' \
  --exclude='./project/target' \
  --exclude='./project/project' \
  . | tar -C "$build" -xf -

# ---- inject a munit test ----------------------------------------------------
echo "-----> Injecting passing munit test"
cat >> "$build/build.sbt" <<'EOF'

libraryDependencies += "org.scalameta" %% "munit" % "1.3.3" % Test
EOF

mkdir -p "$build/src/test/scala"
cat > "$build/src/test/scala/HelloTest.scala" <<'EOF'
class HelloTest extends munit.FunSuite:
  test("arithmetic"):
    assertEquals(1 + 1, 2)
  test("string"):
    assertEquals("hello".toUpperCase, "HELLO")
EOF

# ---- bin/test-compile -------------------------------------------------------
echo
echo "-----> bin/test-compile"
"$buildpack/bin/test-compile" "$build" "$cache" "$env_dir"

# ---- assert source tree survived -------------------------------------------
echo
echo "-----> Verifying test slug layout"
[[ -f $build/build.sbt ]]                       || { echo "FAIL: build.sbt was wiped"; exit 1; }
[[ -f $build/sbt ]]                             || { echo "FAIL: ./sbt was wiped"; exit 1; }
[[ -d $build/src/main/scala ]]                  || { echo "FAIL: src/main/scala missing"; exit 1; }
[[ -d $build/src/test/scala ]]                  || { echo "FAIL: src/test/scala missing"; exit 1; }
[[ -d $build/.heroku-sbt-cache ]]               || { echo "FAIL: in-slug sbt cache missing"; exit 1; }
[[ -d $build/.heroku-sbt-cache/coursier/v1 ]]   || { echo "FAIL: coursier cache not in slug"; exit 1; }
echo "       source tree intact, in-slug cache present"

# ---- assert cache was persisted to CACHE_DIR --------------------------------
[[ -d $cache/sbt-cache ]] || { echo "FAIL: cache not written back to CACHE_DIR"; exit 1; }
echo "       CACHE_DIR/sbt-cache populated for cross-CI-run caching"

# ---- bin/test (no CACHE_DIR — mimics Heroku test dyno) ---------------------
echo
echo "-----> bin/test (no CACHE_DIR, like a real Heroku test dyno)"
"$buildpack/bin/test" "$build" "$env_dir"

echo
echo "-----> OK: bin/test exited 0"
