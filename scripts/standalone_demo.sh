#!/usr/bin/env bash
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Standalone mock gate: teeServer + teeClient + forged Accept reject via Python.
# No Anchor, no SP1 required. Requires lake update (lean-grpc git dep).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d "$ROOT/.lake/packages/lean-grpc" && ! -d "$ROOT/../lean-grpc" ]]; then
  lake update
fi

lake build receiptTests teeServer teeClient goldenVectors

./.lake/build/bin/receiptTests
./.lake/build/bin/goldenVectors

PORT="${LEAN_TEE_PORT:-50071}"
LOG="$(mktemp)"
cleanup() { kill "${PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

LEAN_TEE_PORT="$PORT" LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1 \
  ./.lake/build/bin/teeServer >>"$LOG" 2>&1 &
PID=$!
sleep 0.8

RULES="$(mktemp)"
echo 'allow=vote.yes,vote.no' > "$RULES"
OUT="$(./.lake/build/bin/teeClient 127.0.0.1:$PORT vote.yes "$RULES")"
echo "$OUT" | grep -q evidence_root_hex

export PYTHONPATH="$ROOT/clients/python${PYTHONPATH:+:$PYTHONPATH}"
python3 - <<'PY'
from lean_tee import TeeReceipt, accept_receipt, execute_action

rules = b"allow=vote.yes,vote.no\n"
r = execute_action("vote.yes", rules)
ok, why = accept_receipt(r)
assert ok, why
bad = TeeReceipt(
    code_hash=r.code_hash,
    config_hash=r.config_hash,
    inputs=r.inputs,
    outputs=b"decision=allow\nforged\n",
    nonce=r.nonce,
    result_hash=r.result_hash,
    proof_ref=r.proof_ref,
)
ok2, why2 = accept_receipt(bad)
assert not ok2 and why2 == "resultHash mismatch", (ok2, why2)
print("standalone_demo OK")
PY

echo "standalone_demo OK"
