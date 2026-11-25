#!/usr/bin/env bash
# Native image mode end to end: the native-app fixture (sbt-native-image), with
# the latest sbta release as its launcher, through bin/detect, bin/compile and
# bin/release. The slug must hold only the binary, the Procfile and the
# buildpack's .profile.d script, and the binary must run.
#
# Needs a JDK, gcc and zlib (libz) for linking, and network access (sbt
# dependencies and GraalVM). EXTRA_SBT_SETTINGS, if set, is appended to the
# fixture's build.sbt (for example a NativeLinkerOption where the linker
# can't find zlib).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
buildpack=$(cd "$here/.." && pwd)
src=$here/fixtures/native-app

work=$(mktemp -d)
build="$work/build"
cache="$work/cache"
env_dir="$work/env"
# bin/compile stops the sbt server only when it succeeds; a failed run leaves
# it writing in $build.
cleanup() {
  # shellcheck source=../bin/util/sbt-env.sh
  . "$buildpack/bin/util/sbt-env.sh"
  if [[ -d $build ]] && cd "$build" && sbt_launcher; then sbt_server_stop; fi
  cd / && rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$build" "$cache" "$env_dir"

cp -a "$src"/. "$build"/
curl -fsSL --retry 3 -o "$build/sbta" https://github.com/jamesward/sbta/releases/latest/download/sbta
chmod +x "$build/sbta"
[[ -n ${EXTRA_SBT_SETTINGS:-} ]] && printf '\n%s\n' "$EXTRA_SBT_SETTINGS" >> "$build/build.sbt"

# What heroku/jvm contributes before this buildpack: native mode must drop it.
mkdir -p "$build/.jdk/bin" "$build/.profile.d"
printf '#!/usr/bin/env bash\n' > "$build/.jdk/bin/java"
chmod +x "$build/.jdk/bin/java"
printf 'export PATH="$HOME/.jdk/bin:$PATH"\n' > "$build/.profile.d/jdk.sh"

echo "-----> bin/detect"
"$buildpack/bin/detect" "$build"

echo "-----> bin/compile"
"$buildpack/bin/compile" "$build" "$cache" "$env_dir"

echo "-----> Verifying slug layout"
contents=$(cd "$build" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')
want="./.profile.d ./.profile.d/zz-buildpack-scala.sh ./Procfile ./bin ./bin/native-app "
[[ $contents == "$want" ]] || { echo "FAIL: slug contents '$contents', want '$want'"; exit 1; }
echo "       slug: $contents"

out=$("$build/bin/native-app")
[[ $out == "hello from native-app" ]] || { echo "FAIL: binary printed '$out'"; exit 1; }
echo "       bin/native-app runs: $out"

got=$(env -i bash -c '. "$1"; printf %s "${MALLOC_ARENA_MAX:-}|${JAVA_TOOL_OPTIONS:-}"' _ "$build/.profile.d/zz-buildpack-scala.sh")
[[ $got == "2|" ]] || { echo "FAIL: profile gave '$got', want MALLOC_ARENA_MAX=2 and no JAVA_TOOL_OPTIONS"; exit 1; }

# The GraalVM archive is in the dependency cache, for the next build.
compgen -G "$cache/coursier/v1/https/github.com/graalvm/*" >/dev/null \
  || { echo "FAIL: GraalVM archive not in the build cache"; exit 1; }

echo "-----> bin/release"
release=$("$buildpack/bin/release" "$build")
echo "$release" | sed 's/^/        /'
[[ $release == *"web: bin/native-app"* ]] || { echo "FAIL: release has no web: bin/native-app"; exit 1; }

echo "-----> OK"
