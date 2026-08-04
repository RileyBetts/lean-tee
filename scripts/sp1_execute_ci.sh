#!/usr/bin/env bash
# CI / nightly: SP1 RISC-V execute-only (no CPU prove — avoids OOM on small runners).
# Measured guest is Lean-compiled (`lean_tee_guest_lean`).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.elan/bin:${HOME}/.sp1/bin:${HOME}/.sp1/riscv/bin:${PATH}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/host/target}"
export SP1_PROVER="${SP1_PROVER:-cpu}"
export PROTOC="${PROTOC:-$HOME/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/protoc-bin-vendored-linux-x86_64-3.2.0/bin/protoc}"
export CC_riscv64im_succinct_zkvm_elf="${CC_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/riscv/bin/riscv64-unknown-elf-gcc}"

if ! command -v cargo-prove >/dev/null 2>&1; then
  echo "cargo-prove not on PATH; install via sp1up" >&2
  exit 1
fi
if ! command -v lake >/dev/null 2>&1; then
  echo "lake not on PATH; install Lean 4.32.1 via elan" >&2
  exit 1
fi
if [[ ! -x "${CC_riscv64im_succinct_zkvm_elf}" ]]; then
  echo "missing SP1 C toolchain at ${CC_riscv64im_succinct_zkvm_elf} (sp1up --c-toolchain)" >&2
  exit 1
fi

cd "$ROOT"
echo "== free memory =="
free -h | head -2

echo "== Lean SP1 runtime + guest archive =="
bash scripts/sp1_lean_runtime_fetch.sh
bash scripts/sp1_lean_runtime_build.sh
bash scripts/sp1_lean_guest_build.sh

cd "$ROOT/host"
echo "== build sp1_smoke (Lean guest ELF) =="
cargo build -p lean_tee_prove_server --release --bin sp1_smoke --features sp1

echo "== SP1 execute-only (Lean guest; no prove) =="
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
