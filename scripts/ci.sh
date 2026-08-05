#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

lake build
lake build receiptTests teeServer teeLoopback proveMockServer rustProveLoopback
./.lake/build/bin/receiptTests
./.lake/build/bin/teeLoopback

if command -v pytest >/dev/null 2>&1; then
  PYTHONPATH="$ROOT/clients/python" pytest "$ROOT/clients/python/tests" -q
fi

# Rust Prove host (RISC-V guest logic; mock proof without SP1 toolchain)
export CARGO_TARGET_DIR="$ROOT/host/target"
cd host
cargo test -p lean_tee_compliance
cargo build -p lean_tee_prove_server --release
cd "$ROOT"

export LEAN_TEE_PROVE_PORT=50072
"$CARGO_TARGET_DIR/release/prove_server" &
PROVE_PID=$!
cleanup() { kill "$PROVE_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 0.6
./.lake/build/bin/rustProveLoopback

echo "lean-tee CI OK"
