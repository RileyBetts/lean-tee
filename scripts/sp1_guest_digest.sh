#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Publish ELF + verifying-key digests for the measured Lean SP1 guest.
# Wire Measurement stays codeHash+configHash; these digests pin the executable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/artifacts/sp1_guest_digests.json}"
export PATH="${HOME}/.elan/bin:${HOME}/.sp1/bin:${HOME}/.sp1/riscv/bin:${PATH}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/host/target}"
export SP1_PROVER="${SP1_PROVER:-cpu}"
export PROTOC="${PROTOC:-$HOME/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/protoc-bin-vendored-linux-x86_64-3.2.0/bin/protoc}"
export CC_riscv64im_succinct_zkvm_elf="${CC_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/riscv/bin/riscv64-unknown-elf-gcc}"

if ! command -v cargo-prove >/dev/null 2>&1; then
  echo "cargo-prove not on PATH; install via sp1up" >&2
  exit 1
fi
if [[ ! -x "${CC_riscv64im_succinct_zkvm_elf}" ]]; then
  echo "missing SP1 C toolchain at ${CC_riscv64im_succinct_zkvm_elf}" >&2
  exit 1
fi

cd "$ROOT"
if [[ "${SP1_DIGEST_SKIP_BUILD:-}" != "1" ]]; then
  bash scripts/sp1_lean_runtime_fetch.sh
  bash scripts/sp1_lean_runtime_build.sh
  bash scripts/sp1_lean_guest_build.sh
  cd "$ROOT/host"
  cargo build -p lean_tee_prove_server --release --bin sp1_smoke --features sp1
else
  cd "$ROOT/host"
fi

mkdir -p "$(dirname "$OUT")"
SP1_PROVER=cpu ./target/release/sp1_smoke --print-digests --write-digests "$OUT"
echo "sp1_guest_digest OK → $OUT"
