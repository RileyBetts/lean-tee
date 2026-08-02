# lean-tee threat model

## Goals

- **Integrity:** prove a measured guest ran on given public inputs and produced the claimed outputs.
- **Cheap reject:** adversarial nodes cannot forge `TeeReceipt`s that pass accept + proof check for the active profile.
- **Portable attestation:** no AWS Nitro / cloud PKI root of trust.

## Non-goals

- Confidentiality / sealed memory (Nitro-style secrecy).
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

## Profiles

- **`lean-tee-v1`:** mock proof digest must match; suitable for CI and cheap reject demos.
- **`lean-tee-v2`:** `proof_ref` commits to a host-verified SP1 proof; AcceptReceipt must not accept on client `proof_ok` alone.
