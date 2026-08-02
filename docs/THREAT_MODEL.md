# lean-tee threat model

## Goals

- **Integrity:** prove a measured guest ran on given public inputs and produced the claimed outputs.
- **Cheap reject:** adversarial nodes cannot forge `TeeReceipt`s that pass accept + proof check for the active profile.
- **Portable attestation:** no AWS Nitro / cloud PKI root of trust.

## Non-goals

- Confidentiality / sealed memory (Nitro-style secrecy) — see [VS_NITRO.md](VS_NITRO.md).
- Proving oracle honesty (host-supplied chain views).
- Guaranteed delivery if the prover host censors submissions.
- Full formal verification of the Rust/SP1 host or constraint extractors (v1.0).

## Trust model

| Component | Trust |
| --- | --- |
| Lean `acceptReceipt` + SHA-256 `resultHash` | Trusted checkers (this repo) |
| `lean_tee_receipt` (Rust twin of hash/mock) | Same algorithms; golden-vector gated |
| Guest measurement allow-list / policy file | Governance |
| Mock proof (`lean-tee-v1`) | **Dev/demo only** — not production attestation |
| SP1 RISC-V guest + host verify (`lean-tee-v2`) | Integrity under SP1 + host TCB |
| Client-supplied `proof_ok` | **Not trusted** for non-mock proofs |
| lean-grpc transport | Authenticate with mTLS in production |
| Prover host OS | Untrusted for integrity (proof + hash decide) |

## Receipt binding

```
resultHash = SHA256( len-prefixed(
  "lean-tee/v1", codeHash, configHash, inputs, outputs, nonce))
```

Tampering with outputs without recomputing a valid proof and hash fails verification.

## Profiles / suites

- **`lean-tee-v1` / `sha256+mock`:** mock proof digest; CI and cheap reject demos.
- **`lean-tee-v2` / `sha256+sp1`:** SP1 host-verified `proof_ref`; never accept on client `proof_ok` alone. **Production default** (see [ENTERPRISE.md](ENTERPRISE.md) / [SLA.md](SLA.md)).
- **`blake3+mock`:** optional hash agility; verify with `lean_tee_receipt` (see [CRYPTO.md](CRYPTO.md)).

Unknown `crypto_suite` values fail closed.

## Multi-guest

Only registered first-party `guest_id`s are executable. Unknown/disabled guests fail closed. Distinct `codeHash` per guest (see [API.md](API.md)).
