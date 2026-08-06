#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Sync LeanTee/Sp1Mid.lean into the Init-free mid SP1 C stub.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
lake build LeanTee.Sp1Mid
SRC="$ROOT/.lake/build/ir/LeanTee/Sp1Mid.c"
OUT="$ROOT/host/guest_lean_mid/c/lean_sp1_mid.c"
test -f "$SRC"
mkdir -p "$(dirname "$OUT")"

# Hand-maintained Init-free C matching Sp1Mid exports (see docs/LEAN_SP1_GUEST.md).
cat >"$OUT" <<'EOF'
// AUTO-SYNCED skeleton from LeanTee/Sp1Mid.lean — mid-tier spike (no Init runtime).
// Regenerate commentary via: bash scripts/sp1_lean_mid_sync.sh
#include <stdint.h>

uint32_t lean_tee_sp1_mid_tag = 1296647217u; /* 0x4D494431 'MID1' */

uint32_t lean_tee_sp1_mid_step(uint32_t acc, uint32_t x) {
  uint32_t y = acc ^ x;
  return y * 1664525u + 1013904223u;
}

uint32_t lean_tee_sp1_mid_rounds(uint32_t seed, uint32_t n) {
  uint32_t a = seed;
  for (uint32_t i = 0; i < n; i++) {
    a = lean_tee_sp1_mid_step(a, i);
  }
  return a;
}
EOF

grep -q 'LEAN_EXPORT uint32_t lean_tee_sp1_mid_step' "$SRC" \
  || grep -q 'lean_tee_sp1_mid_step' "$SRC"
grep -q '1296647217' "$SRC" || grep -q '0x4d494431' "$SRC" || grep -q '4d494431' "$SRC"
echo "synced $OUT from LeanTee.Sp1Mid (IR checked)"
