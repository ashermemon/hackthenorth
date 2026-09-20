#!/bin/sh
# Compiles the pure packet logic for the Mac and runs its tests.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/belt_fw_test"
cc -Wall -Wextra -Werror -I"$HERE/../main" "$HERE/test_protocol.c" "$HERE/../main/belt_protocol.c" -o "$OUT"
"$OUT"
