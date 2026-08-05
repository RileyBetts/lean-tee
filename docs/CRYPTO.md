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
| `sha256+mock` | SHA-256 | Mock digest | Empty `crypto_suite` / CI receipts; **not** the production profile |
| `sha256+sp1` | SHA-256 | SP1 proof commitment (`SHA256(bincode(proof))`) | Production prove (`lean-tee-v2`); stamped by `prove_server` after host verify |
| `blake3+mock` | BLAKE3 | Mock digest over BLAKE3 domains | Optional; library + goldens |

**Profile vs suite:** `LEAN_TEE_DEFAULT_PROFILE` defaults to **`lean-tee-v2`**. Production must set `LEAN_TEE_PROVE_ADDR` to an SP1 `prove_server`. Mock demos set `LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1` (or `LEAN_TEE_ALLOW_MOCK_V2=1`).

`ProveResponse.crypto_suite` carries what the prover actually produced. `teeServer` copies it into `ReceiptMeta.crypto_suite` (no longer hardcodes mock).

Domain separation (preimage first chunk):

| Suite | resultHash domain | mock proof domain |
| --- | --- | --- |
| `sha256+mock` | `lean-tee/v1` | `lean-tee/mock-proof/v1` |
| `blake3+mock` | `lean-tee/blake3/v1` | `lean-tee/mock-proof-blake3/v1` |

Within a suite, digests (`codeHash`, `configHash`, `resultHash`, mock `proof_ref`) use that suite’s hash.

## Wire

`ReceiptMeta.crypto_suite` (proto field 4). Empty ⇒ `sha256+mock`.  
`ProveRequest.rules` (field 4): raw config bytes for the compliance path (must hash to `measurement.config_hash` when non-empty).  
`ProveResponse.crypto_suite` (field 3): suite the prover used.

## Verify rules

1. Normalize suite id (empty → `sha256+mock`).
2. If suite unknown → reject.
3. Recompute `resultHash` with that suite’s hash + domain.
4. For `*+mock`, recompute mock proof the same way.
5. For `sha256+sp1` on Lean `teeServer` Accept:
   - Accept if this server previously issued the receipt via Execute (after `prove_server` host-verified), **or**
   - `LEAN_TEE_TRUST_PROOF_OK=1` and client `proof_ok` (external verify path), **else** reject.
6. External verifiers should check SP1 proof + published `vk_*` digests (see `artifacts/sp1_guest_digests.json`).

**Lean teeServer** issues `sha256+mock` / `sha256+sp1` as returned by Prove.  
**`blake3+mock`** is verified via `lean_tee_receipt` (Rust); Lean Accept rejects it with a clear reason so the TCB stays explicit.

## Guardrails

- Do not silently change `sha256+mock` goldens.
- Suites cannot cross-verify (domains differ).
- Do not run `lean-tee-v2` without `LEAN_TEE_PROVE_ADDR` in production.
- `confidentiality=local` forces mock prove and rejects under `lean-tee-v2`.
- Anchor Strict should allow-list suites it can check.

## Env

- `LEAN_TEE_CRYPTO_SUITE` — preferred suite for producers that honor it (Rust clients / future Execute).
- `LEAN_TEE_DEFAULT_PROFILE` — `lean-tee-v2` (default) or `lean-tee-v1`.
- `LEAN_TEE_PROVE_ADDR` — required for v2 (unless `LEAN_TEE_ALLOW_MOCK_V2=1`).
- `LEAN_TEE_TRUST_PROOF_OK` — allow Accept of foreign SP1 receipts when client sets `proof_ok` (after external verify).
