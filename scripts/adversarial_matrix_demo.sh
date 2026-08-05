#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Adversarial matrix: mutate receipt fields; assert reject reasons across Lean / Rust / Python.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
demo_root
require_lean_grpc
export_pythonpath

lake build adversarialMatrix
./.lake/build/bin/adversarialMatrix

cd "$ROOT/host"
cargo run --quiet --example adversarial_matrix -p lean_tee_receipt
cd "$ROOT"

python3 "$ROOT/scripts/adversarial_matrix.py"

echo "adversarial_matrix_demo OK"
