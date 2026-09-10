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
