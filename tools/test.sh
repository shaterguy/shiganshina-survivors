#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export XDG_DATA_HOME="${SHIGAN_TEST_DATA_HOME:-/tmp/shiganshina-godot/data}"
export XDG_CACHE_HOME="${SHIGAN_TEST_CACHE_HOME:-/tmp/shiganshina-godot/cache}"
export XDG_CONFIG_HOME="${SHIGAN_TEST_CONFIG_HOME:-/tmp/shiganshina-godot/config}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
log="$(mktemp /tmp/shiganshina-tests.XXXXXX.log)"
set +e
godot --headless --path "$root" --script tests/run_all.gd -- "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if grep -Eq "^(SCRIPT ERROR:|ERROR:)" "$log"; then exit 1; fi
exit "$status"
