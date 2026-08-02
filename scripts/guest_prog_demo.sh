#!/usr/bin/env bash
# Load a Lean-specified GuestProg via gRPC and Execute on guest_prog_runtime.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
demo_root
require_lean_grpc

lake build teeServer guestProgTests guestProgClient
./.lake/build/bin/guestProgTests

PORT="${LEAN_TEE_PORT:-50084}"
LOG="$(mktemp)"
cleanup() { kill "${PID:-}" 2>/dev/null || true; rm -f "$LOG"; }
trap cleanup EXIT

# Allow guest_prog_runtime for default demo tenant
ACL="$(mktemp)"
cat >"$ACL" <<'EOF'
demo compliance_operator voting_operator onboarding_operator trade_operator guest_prog_runtime
EOF

LEAN_TEE_PORT="$PORT" LEAN_TEE_ACL_FILE="$ACL" \
  ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
wait_port 127.0.0.1 "$PORT"

PROG="$ROOT/examples/guest_programs/demo_votes.prog"
./.lake/build/bin/guestProgClient "127.0.0.1:$PORT" "$PROG" vote.yes | tee /tmp/gp_allow.txt
grep -q 'decision=allow' /tmp/gp_allow.txt
grep -q evidence_root_hex /tmp/gp_allow.txt

./.lake/build/bin/guestProgClient "127.0.0.1:$PORT" "$PROG" trade.submit | tee /tmp/gp_deny.txt
grep -q 'decision=deny' /tmp/gp_deny.txt

rm -f "$ACL"
echo "guest_prog_demo OK"
