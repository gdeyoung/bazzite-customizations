#!/usr/bin/env bash
# Probe contract (identical on Omarchy and KDE — port verbatim, byte-identical):
#  - ONE line of output per invocation, strict JSON object, always exit 0.
#  - No human text, no ANSI, no stderr noise on the happy path.
#  - Guard every `read` against empty matches: bash clobbers pre-initialized
#    vars with "" when the source matches nothing → `"field":,` invalid JSON.
#  - Validate with: ../../../../../tools/check_qml.py <widget> --probe-run <this>
set -euo pipefail
v=0
line=$(grep -m1 '^MemAvailable:' /proc/meminfo || true)
[ -n "$line" ] && read -r _ v _ <<< "$line"
printf '{"value":%s}' "$v"
