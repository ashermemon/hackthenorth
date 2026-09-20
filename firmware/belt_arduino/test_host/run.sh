#!/bin/sh
# Compiles the packet logic for the Mac and runs its tests.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/belt_arduino_test"
c++ -std=c++17 -Wall -Wextra -Werror "$HERE/test_protocol.cpp" -o "$OUT"
"$OUT"
