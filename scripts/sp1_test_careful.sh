#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Staged SP1 tests — avoids proving three cases back-to-back (OOM risk on 16GB).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/platform.sh
source "$ROOT/scripts/lib/platform.sh"
export PATH="${HOME}/.sp1/bin:${PATH}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/host/target}"
export SP1_PROVER="${SP1_PROVER:-cpu}"
export PROTOC="${PROTOC:-$(default_protoc)}"

if ! command -v cargo-prove >/dev/null 2>&1; then
  echo "cargo-prove not on PATH; run: source ~/.bashrc && sp1up" >&2
  exit 1
fi

cd "$ROOT/host"

echo "== free memory =="
print_mem_summary

echo "== Lean SP1 runtime + guest archive =="
cd "$ROOT"
bash scripts/sp1_lean_runtime_fetch.sh
bash scripts/sp1_lean_runtime_build.sh
bash scripts/sp1_lean_guest_build.sh
cd "$ROOT/host"

echo "== build (if needed) =="
cargo build -p lean_tee_prove_server --release --bin sp1_smoke --bin prove_server --features sp1

echo "== SP1 execute-only (all cases, real RISC-V guest) =="
SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only

echo "== SP1 prove+verify one case (default: mock — safe on 16GB laptops) =="
echo "   Real CPU prove is gated (can hard-lock ≤16GB hosts)."
echo "   Prefer GitHub Actions prove_heavy, or: SP1_PROVE_HEAVY=1 SP1_PROVE_HEAVY_FORCE=1 $0"
if [[ "${SP1_PROVE_HEAVY:-}" == "1" ]]; then
  avail_kib="$(mem_available_kib)"
  need_kib=$((10 * 1024 * 1024))
  print_mem_summary
  if [[ "${SP1_PROVE_HEAVY_FORCE:-}" != "1" && "${GITHUB_ACTIONS:-}" != "true" && "${avail_kib}" -lt "${need_kib}" ]]; then
    echo "SP1_PROVE_HEAVY refused: MemAvailable=${avail_kib} KiB (<10 GiB)." >&2
    echo "Do not force on a laptop you care about; use CI prove_heavy / a big machine." >&2
    exit 1
  fi
  SP1_PROVER=cpu ./target/release/sp1_smoke --prove-one 0
else
  SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0
fi

echo "== Lean receipt + loopback =="
cd "$ROOT"
lake build receiptTests teeServer teeLoopback rustProveLoopback
./.lake/build/bin/receiptTests
./.lake/build/bin/teeLoopback

echo "== Lean Tee ↔ Rust Prove (mock mode for gRPC; SP1 already checked above) =="
export LEAN_TEE_PROVE_PORT=50072
export LEAN_TEE_PROVE_MODE=mock
./host/target/release/prove_server &
PROVE_PID=$!
cleanup() { kill "$PROVE_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 0.6
./.lake/build/bin/rustProveLoopback

echo "sp1_test_careful OK"
