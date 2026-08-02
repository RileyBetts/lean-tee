# lean-tee product scope

## What this is

A **standalone integrity-first zkTEE**: run a measured guest, bind public I/O into a hashed receipt, prove (mock or SP1), and verify so downstream systems (e.g. Anchor Chain Strict Mode) can accept or reject evidence cheaply.

## Guarantees by profile

| | `lean-tee-v1` | `lean-tee-v2` |
| --- | --- | --- |
| `resultHash` binding | Yes | Yes |
| Proof | Deterministic mock digest | SP1 Hypercube proof commitment |
| Suitable for | CI, demos, cheap reject | Integrity under SP1 TCB |
| Confidentiality | No | No |

## Non-goals

- Nitro / sealed confidentiality
- Embedding lean-grpc into consumer Lake graphs (call over the wire or use `lean_tee_receipt`)
- Full sail-riscv-lean / sp1-lean end-to-end formalization in v1.0
- Guaranteed delivery if the prover host censors

## Consumers

1. **Direct** — `teeServer` + clients (`teeClient`, Python, Rust)
2. **Library** — depend on `lean_tee_receipt` for hash/mock verify without running Lean
3. **Anchor Strict** — RegisterCompliance fields map to receipt hex; optional live Execute via `LEAN_TEE_ADDR`

## Versioning

- Package / crates: semver (`0.1.0` → `0.2.0` shared crate → `1.0.0` when v2 verify is non-trusting)
- Wire profile strings: `lean-tee-v1` / `lean-tee-v2` (breaking prove semantics bump the profile, not silent)
- Proto package remains `lean_tee.v1` until a wire-incompatible proto change

## lean-grpc pin

Require sibling checkout at **https://github.com/RileyBetts/lean-grpc/tree/v1.0.0** as `../lean-grpc`. GitHub Actions checks out that tag beside this repo.
