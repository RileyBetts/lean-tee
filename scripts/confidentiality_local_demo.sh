#!/usr/bin/env bash
# Local confidentiality=local demo (no Nitro / cloud).
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
demo_root
require_lean_grpc

cd "$ROOT/host"
cargo build -p lean_tee_confidential --release
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/host/target}"
WORKER="$TARGET_DIR/release/sealed_worker"
test -x "$WORKER"

cd "$ROOT"
lake build teeServer confidentialClient

PORT="${LEAN_TEE_PORT:-50085}"
LOG="$(mktemp)"
SECRET="$(mktemp)"
ACL="$(mktemp)"
AUDIT="$(mktemp)"
cleanup() { kill "${PID:-}" 2>/dev/null || true; rm -f "$LOG" "$SECRET" "$ACL" "$AUDIT"; }
trap cleanup EXIT

printf 'allow=vote.yes,vote.no\n' >"$SECRET"
cat >"$ACL" <<'EOF'
demo compliance_operator voting_operator onboarding_operator trade_operator guest_prog_runtime
secret_inputs demo
load_program demo
EOF

LEAN_TEE_PORT="$PORT" \
  LEAN_TEE_ACL_FILE="$ACL" \
  LEAN_TEE_TENANT=demo \
  LEAN_TEE_AUDIT_FILE="$AUDIT" \
  LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1 \
  LEAN_TEE_CONFIDENTIALITY=local \
  LEAN_TEE_SEALED_WORKER="$WORKER" \
  ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
wait_port 127.0.0.1 "$PORT"

./.lake/build/bin/confidentialClient "127.0.0.1:$PORT" vote.yes "$SECRET" | tee /tmp/conf_ok.txt
grep -q 'confidentiality=local' /tmp/conf_ok.txt
grep -q 'secret_digest_hex=' /tmp/conf_ok.txt
grep -q 'decision=allow' /tmp/conf_ok.txt
grep -q 'confidentialClient OK' /tmp/conf_ok.txt

# Audit must not contain raw allow= secret line
if grep -q 'allow=vote.yes' "$AUDIT" 2>/dev/null; then
  echo "FAIL: secret leaked into audit" >&2
  cat "$AUDIT" >&2
  exit 1
fi
grep -q 'confidentiality' "$AUDIT"

# Mode=off must reject secret_inputs
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
LEAN_TEE_PORT="$PORT" LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1 \
  LEAN_TEE_CONFIDENTIALITY=off \
  ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
wait_port 127.0.0.1 "$PORT"
if ./.lake/build/bin/confidentialClient "127.0.0.1:$PORT" vote.yes "$SECRET" >/tmp/conf_off.txt 2>&1; then
  echo "expected reject when confidentiality=off" >&2
  cat /tmp/conf_off.txt >&2
  exit 1
fi
grep -qiE 'secret_inputs|confidentiality|Execute failed' /tmp/conf_off.txt

echo "confidentiality_local_demo OK"
