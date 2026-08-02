#!/usr/bin/env bash
# Action matrix: per-guest allow/deny (live + Python + Rust).
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
demo_root
require_lean_grpc
export_pythonpath

lake build teeServer teeClient guestRegistry
./.lake/build/bin/guestRegistry

PORT="${LEAN_TEE_PORT:-50081}"
LOG="$(mktemp)"
RULES="$(mktemp)"
cleanup() { kill "${PID:-}" 2>/dev/null || true; rm -f "$LOG" "$RULES"; }
trap cleanup EXIT

echo 'rules=v1' >"$RULES"

LEAN_TEE_PORT="$PORT" ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
wait_port 127.0.0.1 "$PORT"

expect_live() {
  local guest="$1" action="$2" want="$3"
  local out
  out="$(./.lake/build/bin/teeClient "127.0.0.1:$PORT" "$action" "$RULES" "$guest")"
  python3 - "$out" "$want" "$guest" "$action" <<'PY'
import json, sys
raw, want, guest, action = sys.argv[1:5]
d = json.loads(raw)
outputs = bytes.fromhex(d["outputs_hex"]).decode()
if not outputs.startswith(f"decision={want}\n"):
    raise SystemExit(f"live {guest}/{action}: want {want} got {outputs!r}")
print(f"live {guest} {action} -> {want}")
PY
}

expect_live compliance_operator vote.yes allow
expect_live voting_operator vote.yes allow
expect_live voting_operator trade.submit deny
expect_live onboarding_operator supplier.register allow
expect_live onboarding_operator vote.yes deny
expect_live trade_operator trade.submit allow
expect_live trade_operator vote.yes deny
expect_live compliance_operator transfer.funds deny

python3 - <<'PY'
from lean_tee import execute_local, accept_receipt

cases = [
    ("compliance_operator", "vote.yes", "allow"),
    ("voting_operator", "vote.yes", "allow"),
    ("voting_operator", "trade.submit", "deny"),
    ("onboarding_operator", "supplier.register", "allow"),
    ("trade_operator", "trade.submit", "allow"),
    ("trade_operator", "vote.yes", "deny"),
]
rules = b"rules=v1\n"
for guest, action, want in cases:
    r = execute_local(action, rules, guest_id=guest, interaction_id=f"{guest}-{action}")
    ok, why = accept_receipt(r)
    assert ok, why
    assert r.outputs.startswith(f"decision={want}\n".encode()), (guest, action, r.outputs)
    print(f"py {guest} {action} -> {want}")
PY

cd "$ROOT/host"
cargo run --quiet --example action_matrix -p lean_tee_compliance
cd "$ROOT"

echo "action_matrix_demo OK"
