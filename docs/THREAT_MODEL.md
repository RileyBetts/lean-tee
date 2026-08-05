# lean-tee threat model

## Goals

- **Integrity:** prove a measured guest ran on given public inputs and produced the claimed outputs.
- **Cheap reject:** adversarial nodes cannot forge `TeeReceipt`s that pass accept + proof check for the active profile.
- **Portable attestation:** no AWS Nitro / cloud PKI root of trust.

## Non-goals

- Hardware sealed memory / Nitro-equivalent isolation by default — see [VS_NITRO.md](VS_NITRO.md).
- Optional **local** confidentiality (`LEAN_TEE_CONFIDENTIALITY=local`) is process isolation + secret hygiene only — see [CONFIDENTIALITY.md](CONFIDENTIALITY.md); it does **not** stop local root. **Incompatible with `lean-tee-v2` / SP1** (the zk guest cannot see secret bytes).
- Proving oracle honesty (host-supplied chain views).
- Guaranteed delivery if the prover host censors submissions.
- Full formal verification of the Rust/SP1 host or constraint extractors (v1.0).
- Lean Accept re-verifying raw SP1 proof bytes (see below).

## Trust model

| Component | Trust |
| --- | --- |
| Lean `acceptReceipt` + SHA-256 `resultHash` | Trusted checkers (this repo) |
| `lean_tee_receipt` (Rust twin of hash/mock) | Same algorithms; golden-vector gated |
| Guest measurement allow-list / policy file | Governance |
| Mock proof (`lean-tee-v1` / `sha256+mock`) | **Dev/demo only** — not production attestation |
| SP1 RISC-V guest + host verify (`lean-tee-v2`) | Integrity under SP1 + host TCB; `prove_server` verifies before advertising `proof_ref` |
| Lean `AcceptReceipt` for `sha256+sp1` | Accepts receipts **this teeServer issued** after host-verified Prove, or `LEAN_TEE_TRUST_PROOF_OK=1` after external verify |
| Client-supplied `proof_ok` | **Not trusted** unless `LEAN_TEE_TRUST_PROOF_OK=1` |
| Published `elf_sha256` / `vk_*` digests | Must be pinned by counterparties (off-wire today) |
| lean-grpc transport | Authenticate with mTLS in production |
| Prover host OS | Untrusted for integrity (proof + hash decide) |
| `confidentiality=local` sealed worker | Secrets out of receipts/logs; **not** from local root; mock suite only |

## Measurement binding

Wire `codeHash` is `SHA256(code_id)` for a registered guest (logical identity). The SP1 guest **also reads `codeHash` and optional `rules` bytes** and selects the builtin allow-surface (or GuestProg). Empty `program` + unknown `codeHash` → deny.

Executable pin is **off-wire**: [`artifacts/sp1_guest_digests.json`](../artifacts/sp1_guest_digests.json) (`elf_sha256`, `vk_bytes32`). Counterparties must pin those in addition to `codeHash` until a future profile folds them into `Measurement`.

## Receipt binding

```
resultHash = SHA256( len-prefixed(
  "lean-tee/v1", codeHash, configHash, inputs, outputs, nonce))
```

Tampering with outputs without recomputing a valid proof and hash fails verification.

## Profiles / suites

- **`lean-tee-v1` / `sha256+mock`:** mock proof digest; CI and cheap reject demos. Default for mock demos.
- **`lean-tee-v2` / `sha256+sp1`:** SP1 host-verified `proof_ref`. **Production default.** Requires `LEAN_TEE_PROVE_ADDR`. Without it, the server **refuses to start** unless `LEAN_TEE_ALLOW_MOCK_V2=1`.
- **`blake3+mock`:** optional hash agility; verify with `lean_tee_receipt` (see [CRYPTO.md](CRYPTO.md)).

Unknown `crypto_suite` values fail closed.

## Multi-guest

Registered `guest_id`s map to distinct `codeHash` values. The SP1 guest enforces the matching builtin action surface (or GuestProg for `guest_prog_runtime`). Unknown/disabled guests fail closed on the host; unknown `codeHash` inside the guest yields `decision=deny`.

## Optional local confidentiality

When enabled (`lean-tee-v1` only), `secret_inputs` are handled by the local sealed worker; PublicIO binds `secret_digest` only. Receipts use **mock** prove. See [CONFIDENTIALITY.md](CONFIDENTIALITY.md).
