#!/bin/sh
# Compiles the pure belt logic (no ARKit) plus the tests for macOS and runs them.
# Usage: App/BeltSelfTest/run.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
BELT="$HERE/../Blind Sight/Belt"
OUT="${TMPDIR:-/tmp}/belt_selftest"
swiftc -O -swift-version 5 -default-isolation MainActor \
  "$BELT/BeltTuning.swift" "$BELT/DepthProcessor.swift" "$BELT/IntensityMapper.swift" "$BELT/DistanceFilter.swift" \
  "$BELT/BeltCommand+Zones.swift" "$BELT/../Core/Models.swift" "$BELT/../Core/BeltProtocol.swift" \
  "$HERE/main.swift" -o "$OUT"
"$OUT"
