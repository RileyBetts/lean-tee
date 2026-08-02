#!/usr/bin/env bash
# Lean Tee ↔ Rust Prove (mock): Execute → AcceptReceipt via rustProveLoopback.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
demo_root
require_lean_grpc

lake build teeServer rustProveLoopback

export CARGO_TARGET_DIR="$ROOT/host/target"
cd "$ROOT/host"
# Rebuild only if missing (avoids accidental sandbox/cache target dirs).
if [[ ! -x "$CARGO_TARGET_DIR/debug/prove_server" ]]; then
  cargo build -p lean_tee_prove_server
fi
cd "$ROOT"

PROVE_PORT="${LEAN_TEE_PROVE_PORT:-50082}"
export LEAN_TEE_PROVE_PORT="$PROVE_PORT"
export LEAN_TEE_PROVE_MODE=mock

LOG="$(mktemp)"
cleanup() { kill "${PROVE_PID:-}" 2>/dev/null || true; rm -f "$LOG"; }
trap cleanup EXIT

"$CARGO_TARGET_DIR/debug/prove_server" >>"$LOG" 2>&1 &
PROVE_PID=$!
wait_port 127.0.0.1 "$PROVE_PORT"

./.lake/build/bin/rustProveLoopback

echo "prove_mock_loopback_demo OK"
