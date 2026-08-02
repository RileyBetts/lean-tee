# lean-tee crypto assurance

## How wide is assurance today?

Integrity only (no confidentiality). One default hash and two prove modes:

| Layer | Default | Strength |
| --- | --- | --- |
| Receipt binding | SHA-256, domain `lean-tee/v1` | Cheap reject of tampered I/O |
| Prove `sha256+mock` / profile `lean-tee-v1` | Mock digest | Demo/CI only |
| Prove `sha256+sp1` / profile `lean-tee-v2` | SP1 Hypercube | zkVM + host verify TCB |

## CryptoSuites (registered choice)

Consumers choose a **named suite**, not an open plugin ABI. Unknown suites **fail closed**.

| Suite id | Hash | Prove | Status |
| --- | --- | --- | --- |
| `sha256+mock` | SHA-256 | Mock digest | **Default**; ≡ empty `crypto_suite` / `lean-tee-v1` |
| `sha256+sp1` | SHA-256 | SP1 proof commitment | `lean-tee-v2` |
| `blake3+mock` | BLAKE3 | Mock digest over BLAKE3 domains | Optional; library + goldens |

Domain separation (preimage first chunk):

| Suite | resultHash domain | mock proof domain |
| --- | --- | --- |
| `sha256+mock` | `lean-tee/v1` | `lean-tee/mock-proof/v1` |
| `blake3+mock` | `lean-tee/blake3/v1` | `lean-tee/mock-proof-blake3/v1` |

Within a suite, digests (`codeHash`, `configHash`, `resultHash`, mock `proof_ref`) use that suite’s hash.

## Wire

`ReceiptMeta.crypto_suite` (proto field 4). Empty ⇒ `sha256+mock`.

## Verify rules

1. Normalize suite id (empty → `sha256+mock`).
2. If suite unknown → reject.
3. Recompute `resultHash` with that suite’s hash + domain.
4. For `*+mock`, recompute mock proof the same way.
5. For `*+sp1`, require host-verified proof (never client `proof_ok` alone).

**Lean teeServer** issues and Accept-checks `sha256+mock` / `sha256+sp1` (host trust flag).  
**`blake3+mock`** is verified via `lean_tee_receipt` (Rust); Lean Accept rejects it with a clear reason so the TCB stays explicit.

## Guardrails

- Do not silently change `sha256+mock` goldens.
- Suites cannot cross-verify (domains differ).
- Anchor Strict should allow-list suites it can check (`sha256+mock` today).

## Env

- `LEAN_TEE_CRYPTO_SUITE` — preferred suite for producers that honor it (Rust clients / future Execute). Default `sha256+mock`.
