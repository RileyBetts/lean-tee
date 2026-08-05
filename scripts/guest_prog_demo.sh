#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

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
cleanup() { kill "${PID:-}" 2>/dev/null || true; rm -f "$LOG" "$ACL"; }
trap cleanup EXIT

# Allow guest_prog_runtime + LoadProgram for demo; deny LoadProgram for votes-only
ACL="$(mktemp)"
cat >"$ACL" <<'EOF'
demo compliance_operator voting_operator onboarding_operator trade_operator guest_prog_runtime
votes-only voting_operator
load_program demo
EOF

LEAN_TEE_PORT="$PORT" LEAN_TEE_ACL_FILE="$ACL" LEAN_TEE_TENANT=demo \
  LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1 \
  ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
wait_port 127.0.0.1 "$PORT"

PROG_V1="$ROOT/examples/guest_programs/demo_votes.prog"
./.lake/build/bin/guestProgClient "127.0.0.1:$PORT" "$PROG_V1" vote.yes | tee /tmp/gp_allow.txt
grep -q 'decision=allow' /tmp/gp_allow.txt
grep -q evidence_root_hex /tmp/gp_allow.txt

./.lake/build/bin/guestProgClient "127.0.0.1:$PORT" "$PROG_V1" trade.submit | tee /tmp/gp_deny.txt
grep -q 'decision=deny' /tmp/gp_deny.txt

PROG_V2="$ROOT/examples/guest_programs/demo_votes_v2.prog"
./.lake/build/bin/guestProgClient "127.0.0.1:$PORT" "$PROG_V2" vote.yes | tee /tmp/gp_v2.txt
grep -q 'decision=allow' /tmp/gp_v2.txt
./.lake/build/bin/guestProgClient "127.0.0.1:$PORT" "$PROG_V2" vote.admin | tee /tmp/gp_v2_deny.txt
grep -q 'decision=deny' /tmp/gp_v2_deny.txt

# LoadProgram ACL: votes-only tenant cannot load
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
LEAN_TEE_PORT="$PORT" LEAN_TEE_ACL_FILE="$ACL" LEAN_TEE_TENANT=votes-only \
  LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1 \
  ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
wait_port 127.0.0.1 "$PORT"
if ./.lake/build/bin/guestProgClient "127.0.0.1:$PORT" "$PROG_V1" vote.yes >/tmp/gp_acl.txt 2>&1; then
  echo "expected LoadProgram ACL deny for votes-only" >&2
  cat /tmp/gp_acl.txt >&2
  exit 1
fi
grep -qiE 'LoadProgram failed|cannot LoadProgram|permission|acl' /tmp/gp_acl.txt

echo "guest_prog_demo OK"
