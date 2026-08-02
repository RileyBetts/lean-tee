# lean-tee API

Wire contract: [`proto/lean_tee/v1/tee.proto`](../proto/lean_tee/v1/tee.proto)  
Transport: [lean-grpc](https://github.com/RileyBetts/lean-grpc) (h2c locally; TLS/mTLS for real adapters)

## Profiles

| Profile | `proof_ref` | Accept |
| --- | --- | --- |
| `lean-tee-v1` | Mock: `SHA256(len-prefixed("lean-tee/mock-proof/v1", code, config, inputs, outputs))` | Hash + mock equality |
| `lean-tee-v2` | `SHA256(bincode(SP1 proof))` after host prove+verify | Host must have verified SP1; client `proof_ok` alone is insufficient |

## Services

| Service | Methods |
| --- | --- |
| `lean_tee.v1.Tee` | `Execute`, `GetReceipt`, `Measure` |
| `lean_tee.v1.Prove` | `Prove` |
| `lean_tee.v1.Verify` | `AcceptReceipt` |
| `lean_tee.v1.AnchorSink` | `Submit` |

Lean stubs: `LeanTee.Grpc`. Pure accept logic: `LeanTee.TeeReceipt.acceptReceipt`.  
Rust shared crypto: `lean_tee_receipt`.

## Field semantics (important)

| Proto field | Meaning |
| --- | --- |
| `ExecuteRequest.config_hash` / `MeasureRequest.config_hash` | **Raw rules / config bytes**, not a precomputed digest. Server stores `configHash = SHA256(rules)` in the measurement. |
| `ExecuteRequest.guest_id` | Guest registry key (UTF-8). Empty → default compliance operator. |
| `ExecuteRequest.inputs` | UTF-8 framing; see binding helpers below. |
| `TeeReceipt.result_hash` | `SHA256(len-prefixed("lean-tee/v1", codeHash, configHash, inputs, outputs, nonce))` |
| `AcceptReceiptRequest.proof_ok` | Hint only for non-mock proofs; Verify re-checks mock locally and requires host-verified SP1 for v2. |
| `AcceptReceiptRequest.policy_*` | Optional measurement allow-list entry; combined with server `LEAN_TEE_POLICY_FILE` |

## Guest model

Default guest: compliance operator (`codeHash = SHA256("lean-tee/compliance_operator/v1")`).

**Rules bytes** (hashed into `configHash`) may include an allow-list line:

```
allow=vote.yes,vote.no,supplier.register,purchaser.approve,purchaser.reject,trade.submit
```

If `allow=` is absent, the built-in default prefixes are used. Actions not listed → `decision=deny` (receipt still well-formed).

### Interaction binding (for Anchor / multi-party)

Canonical input framing:

```
action=<name>
interaction=<id>
<optional payload lines>
```

Helper: `lean_tee_receipt::bind_interaction` / Python `bind_interaction`. Downstream ledgers should require the attested `action` / `interaction` to match the later act (cast, submit side, …).

## Clients

| Client | Path |
| --- | --- |
| CLI | `lake build teeClient` → `.lake/build/bin/teeClient` |
| Python | `clients/python` |
| Rust | `clients/rust` (`lean_tee_client`) |
