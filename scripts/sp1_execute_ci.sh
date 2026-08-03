#!/usr/bin/env bash
# CI / nightly: SP1 RISC-V execute-only (no CPU prove — avoids OOM on small runners).
# Production integrity path credibility without chaining heavy proves.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.sp1/bin:${PATH}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/host/target}"
export SP1_PROVER="${SP1_PROVER:-cpu}"
export PROTOC="${PROTOC:-$HOME/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/protoc-bin-vendored-linux-x86_64-3.2.0/bin/protoc}"

if ! command -v cargo-prove >/dev/null 2>&1; then
  echo "cargo-prove not on PATH; install via sp1up" >&2
  exit 1
fi

cd "$ROOT/host"
echo "== free memory =="
free -h | head -2

echo "== build sp1_smoke (release) =="
cargo build -p lean_tee_prove_server --release --bin sp1_smoke --features sp1

echo "== SP1 execute-only (real RISC-V guest; no prove) =="
SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only

if [[ "${SP1_PROVE_ONE:-}" == "1" ]]; then
  echo "== optional single mock prove (set SP1_PROVE_HEAVY=1 for CPU prove) =="
  if [[ "${SP1_PROVE_HEAVY:-}" == "1" ]]; then
    SP1_PROVER=cpu ./target/release/sp1_smoke --prove-one 0
  else
    SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0
  fi
fi

echo "sp1_execute_ci OK"
