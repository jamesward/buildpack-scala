#!/usr/bin/env bash
# Verify that bin/compile honours the SBT_PROJECT env var by scoping every
# sbt invocation to "<project>/...". Uses a stub ./sbt so we don't depend on
# a real multi-project build to be available.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
buildpack=$(cd "$here/.." && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
build="$work/build"
cache="$work/cache"
env_dir="$work/env"
log="$work/sbt-stub.log"
fake_stage="$work/fake-staging-dir"
mkdir -p "$build" "$cache" "$env_dir" "$build/project" "$fake_stage"

# Minimal sbt "project" so bin/detect succeeds (build.sbt + ./sbt present)
touch "$build/build.sbt"

# Stub ./sbt: records every invocation's args, fakes a `show` value.
cat > "$build/sbt" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\$*" in
  *show*)
    # bin/compile parses lines that match: ^[info] /<no-spaces>$
    echo "[info] $fake_stage"
    ;;
esac
exit 0
EOF
chmod +x "$build/sbt"

# Pass SBT_PROJECT through Heroku-style ENV_DIR (one file per config var)
echo -n "myproj" > "$env_dir/SBT_PROJECT"

# Run bin/compile (the stub returns success and a real-but-empty staging dir)
"$buildpack/bin/compile" "$build" "$cache" "$env_dir" >/dev/null 2>&1 \
  || { echo "FAIL: bin/compile exited non-zero"; exit 1; }

echo "sbt invocations recorded:"
nl -ba "$log" | sed 's/^/  /'
echo

grep -qx 'myproj/stage' "$log" \
  || { echo "FAIL: did not see 'myproj/stage' in sbt args"; exit 1; }

grep -q 'show myproj / Universal / stagingDirectory' "$log" \
  || { echo "FAIL: did not see scoped show command"; exit 1; }

echo "OK: bin/compile invoked sbt with SBT_PROJECT=myproj scoping"
