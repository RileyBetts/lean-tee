#!/usr/bin/env bash
# Cross-impl golden: Lean (sha256) + Rust (both suites) + Python twin.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
demo_root
require_lean_grpc
export_pythonpath

lake build goldenVectors
./.lake/build/bin/goldenVectors
echo "lean golden_v1 OK (sha256+mock; blake3 is Rust/Python only)"

cd "$ROOT/host"
cargo test -p lean_tee_receipt --quiet golden_ -- --nocapture
cd "$ROOT"

python3 "$ROOT/scripts/cross_impl_golden.py"

echo "cross_impl_golden_demo OK"
