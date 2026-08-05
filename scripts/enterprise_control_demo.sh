#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Enterprise control plane smoke: ACL + audit + job dir + metrics.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
demo_root
require_lean_grpc
export_pythonpath

lake build teeServer teeClient

PORT="${LEAN_TEE_PORT:-50083}"
LOG="$(mktemp)"
RULES="$(mktemp)"
AUDIT="$(mktemp)"
JOBDIR="$(mktemp -d)"
cleanup() { kill "${PID:-}" 2>/dev/null || true; rm -f "$LOG" "$RULES" "$AUDIT"; rm -rf "$JOBDIR"; }
trap cleanup EXIT

echo 'rules=v1' >"$RULES"

LEAN_TEE_PORT="$PORT" \
LEAN_TEE_ACL_FILE="$ROOT/config/acl.example.txt" \
LEAN_TEE_TENANT=votes-only \
LEAN_TEE_AUDIT_FILE="$AUDIT" \
LEAN_TEE_JOB_DIR="$JOBDIR" \
LEAN_TEE_METRICS=1 \
LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1 \
  ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
wait_port 127.0.0.1 "$PORT"

# votes-only tenant may use voting_operator
./.lake/build/bin/teeClient "127.0.0.1:$PORT" vote.yes "$RULES" voting_operator | grep -q evidence_root_hex

# trade forbidden for votes-only
set +e
OUT="$(./.lake/build/bin/teeClient "127.0.0.1:$PORT" trade.submit "$RULES" trade_operator 2>&1)"
EC=$?
set -e
if [[ "$EC" -eq 0 ]]; then
  echo "ACL should forbid trade_operator for votes-only" >&2
  echo "$OUT" >&2
  exit 1
fi
echo "$OUT" | grep -qi 'acl\|forbid\|error'

grep -q '"event":"execute"' "$AUDIT"
test -n "$(find "$JOBDIR" -name '*.ok' | head -1)"

echo "enterprise_control_demo OK"
