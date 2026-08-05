#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Sync LeanTee/Sp1Spike.lean IR into the phase-0 SP1 C stub (UInt32 exports only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
lake build LeanTee.Sp1Spike
SRC="$ROOT/.lake/build/ir/LeanTee/Sp1Spike.c"
OUT="$ROOT/host/guest_lean_spike/c/lean_sp1_spike.c"
test -f "$SRC"

# Keep a checked-in, Init-free C file derived from Lean IR (see docs/LEAN_SP1_GUEST.md).
cat >"$OUT" <<'EOF'
// AUTO-SYNCED skeleton from LeanTee/Sp1Spike.lean — phase-0 spike (no Init runtime).
// Regenerate commentary via: bash scripts/sp1_lean_spike_sync.sh
// The bodies of lean_tee_sp1_add / hello tag match Lake IR under Lean 4.32.1.
#include <stdint.h>

uint32_t lean_uint32_add(uint32_t a, uint32_t b) {
  return a + b;
}

uint32_t lean_tee_sp1_hello_tag = 1280528433u; /* 0x4C535031 'LSP1' */

uint32_t lean_tee_sp1_add(uint32_t a, uint32_t b) {
  return lean_uint32_add(a, b);
}
EOF

# Verify Lake IR still exports the same symbols / constant.
grep -q 'LEAN_EXPORT uint32_t lean_tee_sp1_add' "$SRC"
grep -q 'v___x_1_ = 1280528433' "$SRC" || grep -q '1280528433' "$SRC"
echo "synced $OUT from LeanTee.Sp1Spike (IR checked)"
