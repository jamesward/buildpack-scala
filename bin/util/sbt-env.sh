#!/usr/bin/env bash
# bin/util/sbt-env.sh
# Sourced by bin/compile, bin/test-compile, bin/test.
#
# Defines:
#   sbt_env_configure <dependency-cache-root> <task-cache-root>
#       Sets COURSIER_CACHE and SBT_OPTS so subsequent `./sbt` invocations
#       use <dependency-cache-root>/{coursier,ivy2,sbt}/... for dependency
#       resolution and the sbt launcher, while sbt 2's automatic task-output
#       cache uses <task-cache-root>.
#   sbt_server_stop
#       Stops the background sbt server for the current directory and waits
#       for it to exit.
#
# These roots deliberately have different lifetimes. Dependency downloads are
# safe to persist between builds. sbt 2 task outputs are not: an under-keyed
# plugin task can restore an artifact generated for an older dependency graph
# (observed with sbt-native-packager's launcher JAR). Callers therefore pass a
# build-scoped task cache while retaining the long-lived dependency cache.

# shellcheck shell=bash

sbt_env_configure() {
  local cache_root=${1:-}
  local task_cache_root=${2:-}
  if [[ -z $cache_root || -z $task_cache_root ]]; then
    echo "sbt_env_configure: dependency and task cache root paths required" >&2
    return 1
  fi

  local coursier_cache="$cache_root/coursier/v1"
  local ivy_home="$cache_root/ivy2"
  local sbt_boot="$cache_root/sbt/boot"
  local sbt_global="$cache_root/sbt"

  mkdir -p "$coursier_cache" "$ivy_home" "$sbt_boot" "$sbt_global" "$task_cache_root"

  export COURSIER_CACHE="$coursier_cache"
  export SBT_OPTS="${SBT_OPTS:-} -Dsbt.boot.directory=$sbt_boot -Dsbt.global.base=$sbt_global -Dsbt.global.localcache=$task_cache_root -Dsbt.ivy.home=$ivy_home -Divy.home=$ivy_home"
}

# The project's sbt launcher: ./sbta (sbt plus an MCP server, https://github.com/jamesward/sbta)
# when the project has one, else ./sbt. Both take sbt's arguments. Sets SBT to "./sbta" or "./sbt"
# and makes it executable; call it from the build directory.
sbt_launcher() {
  if [[ -f ./sbta ]]; then SBT=./sbta
  elif [[ -f ./sbt ]]; then SBT=./sbt
  else return 1
  fi
  chmod +x "$SBT"
}

# Stop the sbt server that the thin client (sbt 2's default, and ./sbta's)
# left running in the background for the current directory, and wait for its
# JVM to exit. The server keeps writing under target/ after each client command
# returns (it rotates target/global-logging/ files) and again while it exits,
# so deleting target/ while it is alive races it: `rm -rf` fails with
# "Directory not empty". `shutdown` returns before the JVM exits, hence the
# wait. Without a running server (no project/target/active.json) this does
# nothing, so a launcher without a server isn't started just to stop. Call it
# from the build directory after the last sbt command; it never fails.
sbt_server_stop() {
  [[ -f project/target/active.json ]] || return 0
  local dir pid deadline
  dir=$(pwd -P)
  "$SBT" shutdown >/dev/null 2>&1 || true
  deadline=$((SECONDS + 30))
  while [[ -n $(sbt_server_pids "$dir") ]] && ((SECONDS < deadline)); do
    sleep 0.1
  done
  for pid in $(sbt_server_pids "$dir"); do
    kill -9 "$pid" 2>/dev/null || true
  done
  return 0
}

# sbt_server_pids <dir>: the JVMs (sbt servers) whose working directory is <dir>.
sbt_server_pids() {
  local p
  for p in $(pgrep java 2>/dev/null || true); do
    [[ $(readlink "/proc/$p/cwd" 2>/dev/null) == "$1" ]] && echo "$p"
  done
  return 0
}
