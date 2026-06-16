#!/usr/bin/env bash
# Smoke-test the buildpack against a copy of ~/projects/hello/hello-zio-http.
#
# This emulates what Heroku does:
#   * stage the app source in a fresh BUILD_DIR
#   * provide a CACHE_DIR
#   * run bin/detect, bin/compile, bin/release
#   * assert the resulting slug layout
#
# It does NOT actually launch the app — it just verifies that the buildpack
# turns the source into a runnable slug whose layout matches expectations.
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

# Copy app source, skipping VCS / IDE / build-output / target dirs.
# We use tar so we can exclude paths without depending on rsync.
echo "-----> Staging $src into $build"
tar -C "$src" -cf - \
  --exclude='./.git' \
  --exclude='./.idea' \
  --exclude='./.bsp' \
  --exclude='./target' \
  --exclude='./project/target' \
  --exclude='./project/project' \
  . | tar -C "$build" -xf -

# bin/detect
echo
echo "-----> bin/detect"
detected=$("$buildpack/bin/detect" "$build")
echo "       reported: $detected"
[[ $detected == *"Scala"* ]] || { echo "detect did not report Scala"; exit 1; }

# bin/compile
echo
echo "-----> bin/compile"
"$buildpack/bin/compile" "$build" "$cache" "$env_dir"

# Assert slug layout
echo
echo "-----> Verifying slug layout"
echo "Slug root:"
ls -la "$build" | sed 's/^/        /'

[[ -d $build/bin ]] || { echo "FAIL: $build/bin missing"; exit 1; }
[[ -d $build/lib ]] || { echo "FAIL: $build/lib missing"; exit 1; }

# expect a launcher script
launcher=""
for f in "$build"/bin/*; do
  [[ -f $f && -x $f && $f != *.bat ]] || continue
  launcher=$f
  break
done
[[ -n $launcher ]] || { echo "FAIL: no executable script under bin/"; exit 1; }
echo "       launcher: ${launcher#$build/}"

# At least one jar in lib/
shopt -s nullglob
jars=("$build"/lib/*.jar)
shopt -u nullglob
(( ${#jars[@]} > 0 )) || { echo "FAIL: lib/ has no jars"; exit 1; }
echo "       lib/ has ${#jars[@]} jars"

# Procfile preserved if it was in the source
if [[ -f $src/Procfile ]]; then
  [[ -f $build/Procfile ]] || { echo "FAIL: Procfile not preserved"; exit 1; }
  echo "       Procfile preserved: $(cat "$build/Procfile")"
fi

# bin/release
echo
echo "-----> bin/release"
"$buildpack/bin/release" "$build" | sed 's/^/        /'

echo
echo "-----> OK"
