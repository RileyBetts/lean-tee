# Anchor Strict — multi-guest lean-tee

Sibling [anchor-chain](../../anchor-chain) Strict Mode can attest with **per-interaction guest measurements**.

## Mapping

| Anchor flow | lean-tee `guest_id` | Typical action |
| --- | --- | --- |
| Voting Strict | `voting_operator` | `vote.yes` / `vote.no` |
| Onboarding Strict | `onboarding_operator` | `supplier.register`, `purchaser.approve` / `reject` |
| Bilateral / trade Strict | `trade_operator` | `trade.submit` |
| Generic / legacy | `compliance_operator` (or empty) | any allow-listed action |

## RegisterCompliance

Continue to store hex fields from the receipt (`code_hash_hex`, `config_hash_hex`, `evidence_root_hex`, `proof_ref_hex`, …). Ensure OpenBallot / Negotiate `attestation_profile` matches the suite (`lean-tee-v1` mock demos; `lean-tee-v2` when SP1 host verify is wired).

For **lean-tee-v2**, also pin the SP1 executable digests from [`artifacts/sp1_guest_digests.json`](../artifacts/sp1_guest_digests.json) (`elf_sha256`, `vk_bytes32`). These are **not** on the receipt wire; they bind the verifying key / guest image the prover must use. Regenerate with `bash scripts/sp1_guest_digest.sh` after guest rebuilds.

## Live Execute

```bash
# lean-tee
LEAN_TEE_PORT=50071 lake exe teeServer
# Anchor agents
LEAN_TEE_ADDR=127.0.0.1:50071 LEAN_TEE_GUEST_ID=voting_operator \
  bash scripts/agent_voting_strict_demo.sh
```

Python SDK:

```python
from lean_tee import execute_action
r = execute_action("vote.yes", rules, guest_id="voting_operator", interaction_id=ballot_id)
```

Classic (non-Strict) Anchor demos remain unchanged.

## Detailed write-up

HTML guide: [anchor-strict-lean-tee-attestation.html](anchor-strict-lean-tee-attestation.html) — attestation flow, adversarial third-party node, and reject-before-ledger-act gates.
