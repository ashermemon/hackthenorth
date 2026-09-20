#!/bin/sh
# Compiles the packet and pulse logic for the Mac and runs their tests.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}"
for t in test_protocol test_pulse; do
  echo "== $t"
  c++ -std=c++17 -Wall -Wextra -Werror "$HERE/$t.cpp" -o "$OUT/belt_arduino_$t"
  "$OUT/belt_arduino_$t"
done
