# lean-tee threat model (v1)

## Goals

- **Integrity:** prove a measured guest ran on given public inputs and produced the claimed outputs.
- **Cheap reject:** adversarial nodes cannot forge `TeeReceipt`s that pass `acceptReceipt` + proof check.
- **Portable attestation:** no AWS Nitro / cloud PKI root of trust.

## Non-goals (v1)

- Confidentiality / sealed memory (Nitro-style secrecy).
- Proving oracle honesty (host-supplied chain views).
- Guaranteed delivery if the prover host censors submissions.
- Full formal verification of the Rust/SP1 host or constraint extractors.

## Trust model

| Component | Trust |
| --- | --- |
| Lean `acceptReceipt` + SHA-256 `resultHash` | Trusted checkers (this repo) |
| Guest measurement allow-list | Governance |
| Mock proof (`Guest.mockProof`) / `SP1_PROVER=mock` | **Dev/demo only** |
| SP1 RISC-V guest (`host/guest`, toolchain 6.3.1) | Execution checked via `sp1_smoke --execute-only` |
| SP1 CPU prove (`SP1_PROVER=cpu`) | Real proofs; **high RAM** — use one case at a time |
| sail-riscv-lean / sp1-lean | Cited FV assumptions (not imported end-to-end yet) |
| lean-grpc transport | Authenticate with mTLS in production |
| Prover host OS | Untrusted for integrity (proof + hash decide) |

## Receipt binding

```
resultHash = SHA256( len-prefixed(
  "lean-tee/v1", codeHash, configHash, inputs, outputs, nonce))
```

Tampering with outputs without recomputing a valid proof and hash fails verification.
