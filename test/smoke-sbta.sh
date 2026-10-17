#!/usr/bin/env bash
# The sample app with ./sbta (https://github.com/jamesward/sbta) as its only launcher: no ./sbt.
# Runs the end-to-end smoke test against a copy of it, with the latest sbta release's script.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=${SAMPLE_APP:-$here/fixtures/sample-app}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -a "$src"/. "$work"/
rm -f "$work/sbt" "$work/sbt.bat"
curl -fsSL --retry 3 -o "$work/sbta" https://github.com/jamesward/sbta/releases/latest/download/sbta
chmod +x "$work/sbta"
echo "-----> Sample app with ./sbta and no ./sbt"
SAMPLE_APP=$work "$here/smoke.sh"
