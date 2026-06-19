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
# Mirror sbt-native-packager's real layout: the staging dir always ends in
# `universal/stage`. bin/compile keys on that suffix, so the stub must too.
fake_stage="$build/target/out/jvm/scala-3.8.4/myproj/universal/stage"
fake_base="$build/myproj-dir"
mkdir -p "$build" "$cache" "$env_dir" "$build/project" "$fake_stage" "$fake_base"

# Minimal sbt "project" so bin/detect succeeds (build.sbt + ./sbt present)
touch "$build/build.sbt"

# The subproject ships its own Procfile in its base directory. The buildpack
# should ship *this* one (not a repo-root one) for a multi-project build.
echo -n "web: bin/myproj" > "$fake_base/Procfile"
# A repo-root Procfile that must be ignored in favour of the subproject's.
echo -n "web: bin/should-not-be-used" > "$build/Procfile"

# Stub ./sbt: records every invocation's args, fakes `show` values. The
# baseDirectory query returns a directory distinct from the staging dir so we
# can prove the buildpack reads the subproject's Procfile from it.
cat > "$build/sbt" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\$*" in
  *baseDirectory*)
    echo "[info] $fake_base"
    ;;
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

grep -q 'show myproj / baseDirectory' "$log" \
  || { echo "FAIL: did not see scoped baseDirectory query"; exit 1; }

[[ -f "$build/Procfile" ]] \
  || { echo "FAIL: no Procfile in slug"; exit 1; }
got=$(cat "$build/Procfile")
[[ $got == "web: bin/myproj" ]] \
  || { echo "FAIL: slug Procfile is '$got', expected the subproject's 'web: bin/myproj'"; exit 1; }

echo "OK: bin/compile invoked sbt with SBT_PROJECT=myproj scoping"
echo "OK: bin/compile shipped the subproject's Procfile from its base directory"
