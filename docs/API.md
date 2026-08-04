# lean-tee API

Wire contract: [`proto/lean_tee/v1/tee.proto`](../proto/lean_tee/v1/tee.proto)  
Transport: [lean-grpc](https://github.com/RileyBetts/lean-grpc) (h2c locally; TLS/mTLS for real adapters — see [ENTERPRISE.md](ENTERPRISE.md))

## Profiles / CryptoSuites

| Profile / suite | `proof_ref` | Accept |
| --- | --- | --- |
| `lean-tee-v1` / `sha256+mock` (default for CI) | Mock SHA-256 digest | Hash + mock equality |
| `lean-tee-v2` / `sha256+sp1` (production default) | `SHA256(bincode(SP1 proof))` after host prove+verify | Host must have verified SP1 |
| `blake3+mock` | Mock BLAKE3 digest | Via `lean_tee_receipt` |

See [CRYPTO.md](CRYPTO.md). `ReceiptMeta.crypto_suite` carries the suite id (empty ⇒ `sha256+mock`).

## GuestDescriptor

Normative fields (registry: [`config/guests/registry.json`](../config/guests/registry.json)):

| Field | Meaning |
| --- | --- |
| `guest_id` | Wire key in `ExecuteRequest.guest_id` / `MeasureRequest.guest_id` (UTF-8). Empty ⇒ `compliance_operator`. |
| `code_id` | Preimage of `codeHash` (`SHA256(code_id)` for sha256 suites). |
| `codeHash` | `hash_suite(suite, code_id)` — measurement field. |
| `config_schema` | How raw config bytes are interpreted (hashed into `configHash`). |
| `actions` | Built-in allow prefixes for this guest (`action=<name>`). |
| `default_profile` | `lean-tee-v1` or `lean-tee-v2`. |
| `enabled` | Disabled guests fail closed (`unknown` / disabled). |

| `guest_id` | `code_id` | Built-in actions |
| --- | --- | --- |
| `compliance_operator` | `lean-tee/compliance_operator/lean-sp1/v1` | all six defaults (or `allow=` narrow) |
| `voting_operator` | `lean-tee/voting_operator/lean-sp1/v1` | `vote.yes`, `vote.no` |
| `onboarding_operator` | `lean-tee/onboarding_operator/lean-sp1/v1` | `supplier.register`, `purchaser.approve`, `purchaser.reject` |
| `trade_operator` | `lean-tee/trade_operator/lean-sp1/v1` | `trade.submit` |
| `guest_prog_runtime` | `lean-tee/guest_prog_runtime/lean-sp1/v1` | Lean-compiled GuestProg runtime (not Lean source) |

Unknown or disabled `guest_id` → error. Prefer `LoadProgram` / `Execute.program` / `program_id` for GuestProg (leave `guest_id` empty in that mode) — see [GUEST_PROG.md](GUEST_PROG.md).

## Services

| Service | Methods |
| --- | --- |
| `Tee` | `Execute`, `GetReceipt`, `Measure`, `LoadProgram`, `GetProgram` |
| `lean_tee.v1.Prove` | `Prove` |
| `lean_tee.v1.Verify` | `AcceptReceipt` |
| `lean_tee.v1.AnchorSink` | `Submit` |

Lean stubs: `LeanTee.Grpc`. Pure accept logic: `LeanTee.TeeReceipt.acceptReceipt`.  
Rust shared crypto: `lean_tee_receipt`. Guests: `lean_tee_compliance` + registry.

## Field semantics (important)

| Proto field | Meaning |
| --- | --- |
| `ExecuteRequest.config_hash` / `MeasureRequest.config_hash` | **Raw rules / config bytes**, not a precomputed digest. Server stores `configHash = SHA256(rules)` in the measurement. Ignored when program mode is active. |
| `ExecuteRequest.guest_id` / `MeasureRequest.guest_id` | Guest registry key (UTF-8). Empty → `compliance_operator` unless `program` / `program_id` is set. |
| `ExecuteRequest.program` / `MeasureRequest.program` | Inline GuestProg bytes (`lean-tee-guest-prog/v1` or `/v2`). Sets measurement to runtime `codeHash` + `configHash = SHA256(program)`. |
| `ExecuteRequest.program_id` | Id returned by `LoadProgram` (hex of program hash). Alternative to inline `program`. |
| `ExecuteRequest.secret_inputs` | Secret bytes for `confidentiality=local` only; rejected when mode=off. Never copied into PublicIO. |
| `LoadProgramRequest.program` | GuestProg payload; reject if over `LEAN_TEE_MAX_PROGRAM_BYTES` (default 65536) or tenant not on ACL `load_program` list. |
| `ExecuteRequest.inputs` | UTF-8 framing; see binding helpers below. GuestProg v2 may require `interaction=`. With secrets, server appends `secret_digest=<hex>`. |
| `ReceiptMeta.confidentiality` | Empty or `local`. |
| `ReceiptMeta.secret_digest_hex` | Hex SHA-256 of `secret_inputs` when mode=local. |
| `AcceptReceiptRequest.require_confidentiality` | If `local`, require matching meta + digest. |
| `TeeReceipt.result_hash` | Suite-domain length-prefixed hash over measurement + I/O + nonce |
| `AcceptReceiptRequest.proof_ok` | Hint only for non-mock proofs; Verify re-checks mock locally and requires host-verified SP1 for v2. |
| `AcceptReceiptRequest.policy_*` | Optional measurement allow-list entry; combined with server `LEAN_TEE_POLICY_FILE` |

## Guest model / rules

**Rules bytes** (hashed into `configHash`) may include an allow-list line:

```
allow=vote.yes,vote.no
```

`allow=` may only **narrow** within the guest’s built-in actions. Actions outside the guest surface → `decision=deny` (receipt still well-formed).

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
| CLI | `lake build teeClient` → `.lake/build/bin/teeClient [guest_id]` |
| Python | `clients/python` — `execute_action(..., guest_id=...)` |
| Rust | `clients/rust` (`lean_tee_client`) — `execute_action(..., guest_id)` |
