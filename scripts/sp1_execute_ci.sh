#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

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
if [[ ! -d "$ROOT/.lake/packages/lean-grpc" && ! -d "$ROOT/../lean-grpc" ]]; then
  lake update
fi
echo "== free memory =="
free -h | head -2

echo "== Lean SP1 runtime + guest archive =="
bash scripts/sp1_lean_runtime_fetch.sh
bash scripts/sp1_lean_runtime_build.sh
bash scripts/sp1_lean_guest_build.sh

cd "$ROOT/host"
echo "== build sp1_smoke (Lean guest ELF) =="
cargo build -p lean_tee_prove_server --release --bin sp1_smoke --features sp1

DIGEST_OUT="$ROOT/artifacts/sp1_guest_digests.json"
DIGEST_PINNED="$ROOT/artifacts/sp1_guest_digests.pinned.json"
mkdir -p "$ROOT/artifacts"
if [[ "${SP1_CHECK_DIGESTS:-}" == "1" ]]; then
  if [[ ! -f "$ROOT/artifacts/sp1_guest_digests.json" ]]; then
    echo "missing pinned artifacts/sp1_guest_digests.json" >&2
    exit 1
  fi
  cp "$ROOT/artifacts/sp1_guest_digests.json" "$DIGEST_PINNED"
fi
echo "== SP1 execute-only + guest digests (compliance + GuestProg; Lean guest) =="
SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only \
  --print-digests --write-digests "$DIGEST_OUT"
if [[ "${SP1_CHECK_DIGESTS:-}" == "1" ]]; then
  python3 "$ROOT/scripts/sp1_guest_digests_check.py" "$DIGEST_PINNED" "$DIGEST_OUT"
fi

if [[ "${SP1_PROVE_ONE:-}" == "1" ]]; then
  echo "== optional single prove (case 0 = compliance-allow-yes) =="
  if [[ "${SP1_PROVE_HEAVY:-}" == "1" ]]; then
    # Real CPU prove of the Lean ELF routinely needs >>8 GiB free; on 16 GiB
    # laptops this has hard-locked the machine. Abort unless explicitly forced.
    avail_kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    need_kib=$((10 * 1024 * 1024)) # 10 GiB
    free -h | head -2
    if [[ "${SP1_PROVE_HEAVY_FORCE:-}" != "1" && "${GITHUB_ACTIONS:-}" != "true" && "${avail_kib}" -lt "${need_kib}" ]]; then
      echo "SP1_PROVE_HEAVY refused: MemAvailable=${avail_kib} KiB (<10 GiB)." >&2
      echo "Use Actions prove_heavy / a larger machine, or SP1_PROVE_HEAVY_FORCE=1 (OOM/lockup risk)." >&2
      exit 1
    fi
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      echo "note: GITHUB_ACTIONS runner may still OOM on CPU prove; prefer a larger runner if this fails"
    fi
    echo "SP1_PROVE_HEAVY=1 → real CPU prove (MemAvailable=${avail_kib} KiB)"
    SP1_PROVER=cpu ./target/release/sp1_smoke --prove-one 0
  else
    SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0
  fi
fi

echo "sp1_execute_ci OK"
