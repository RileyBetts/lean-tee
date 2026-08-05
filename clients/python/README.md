# lean-tee Python client

Stdlib-only helpers that mirror `lean_tee_receipt` for local Execute / AcceptReceipt checks.  
Add this directory to `PYTHONPATH` or install in editable mode from the repo root.

## Setup

```bash
export PYTHONPATH="/path/to/lean-tee/clients/python${PYTHONPATH:+:$PYTHONPATH}"
```

Optional tests: `pip install pytest && pytest clients/python/tests -q`

## Local twin (no server)

Build and verify a receipt entirely in Python — same goldens as Lean/Rust:

```python
from lean_tee import execute_local, accept_receipt

rules = b"allow=vote.yes,vote.no\n"
receipt = execute_local(
    "vote.yes",
    rules,
    interaction_id="ballot-1",
)
ok, reason = accept_receipt(receipt)
if not ok:
    raise SystemExit(reason)

print(receipt.as_hex()["evidence_root_hex"])
```

## Live gRPC (teeServer running)

Start the server (mock profile):

```bash
lake build teeServer
LEAN_TEE_PORT=50071 ./.lake/build/bin/teeServer
```

Then:

```python
import os
os.environ["LEAN_TEE_ADDR"] = "127.0.0.1:50071"

from lean_tee import execute_action, accept_receipt

rules = b"allow=vote.yes,vote.no\n"
receipt = execute_action("vote.yes", rules)
ok, reason = accept_receipt(receipt)
assert ok, reason
```

`accept_receipt` validates **mock** suites (`sha256+mock`, `blake3+mock`) only.  
SP1 receipts (`sha256+sp1`) must be verified by the host / `lean_tee_receipt` SP1 path.

## Multi-guest

```python
from lean_tee import execute_local

rules = b"allow=vote.yes,vote.no\n"
receipt = execute_local("vote.yes", rules, guest_id="voting_operator")
```

See [docs/API.md](../../docs/API.md) for `guest_id` and GuestProg modes.

## See also

- [docs/GETTING_STARTED.md](../../docs/GETTING_STARTED.md)
- [scripts/standalone_demo.sh](../../scripts/standalone_demo.sh) — end-to-end mock demo
