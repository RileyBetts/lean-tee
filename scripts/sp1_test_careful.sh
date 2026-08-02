#!/usr/bin/env bash
# Staged SP1 tests — avoids proving three cases back-to-back (OOM risk on 16GB).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.sp1/bin:${PATH}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/host/target}"
export SP1_PROVER="${SP1_PROVER:-cpu}"
export PROTOC="${PROTOC:-$HOME/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/protoc-bin-vendored-linux-x86_64-3.2.0/bin/protoc}"

if ! command -v cargo-prove >/dev/null 2>&1; then
  echo "cargo-prove not on PATH; run: source ~/.bashrc && sp1up" >&2
  exit 1
fi

cd "$ROOT/host"

echo "== free memory =="
free -h | head -2

echo "== build (if needed) =="
cargo build -p lean_tee_prove_server --release --bin sp1_smoke --bin prove_server

echo "== SP1 execute-only (all cases, real RISC-V guest) =="
SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only

echo "== SP1 prove+verify one case (default: mock — safe on 16GB laptops) =="
echo "   For real CPU prove (can OOM): SP1_PROVE_HEAVY=1 $0"
if [[ "${SP1_PROVE_HEAVY:-}" == "1" ]]; then
  free -h | head -2
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
