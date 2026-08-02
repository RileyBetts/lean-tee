# lean-tee product scope

## What this is

A **portable integrity TEE compute platform** for open-source and multi-party systems: run a **registered, measured guest**, bind **public** I/O into a hashed receipt, prove (mock or SP1), and verify so downstream systems can accept honest results or cheaply reject forged evidence.

**Marketing one-liner:** *Open attestation for public compute — Nitro-class integrity claims you can verify anywhere, without Nitro’s confidentiality boundary.*

Not a confidentiality enclave. Full can/can’t matrix vs AWS Nitro: **[VS_NITRO.md](VS_NITRO.md)**.

## Who it is for

- Teams building **compliance / voting / trade** gates where evidence is public but must be unforgeable
- Chains, agents, and ledgers that need **cheap reject** of adversarial receipts
- Enterprises that want **portable** attestation (CI → staging → multi-cloud) without AWS PCR roots
- Builders who prefer a **small guest registry** + Lean/Rust specs over a general enclave VM

## Who should keep Nitro (or similar)

- Workloads that **decrypt secrets**, hold keys, or process regulated data the host must not see
- Apps that need **KMS release-to-enclave** or NSM/PCR attestation inside AWS
- Anyone needing a **drop-in Nitro / vsock** replacement

## Multi-guest registry

First-party operators are selected by `ExecuteRequest.guest_id` (see [API.md](API.md) GuestDescriptor). Empty `guest_id` ⇒ `compliance_operator`.

| `guest_id` | Measurement `CODE_ID` |
| --- | --- |
| `compliance_operator` | `lean-tee/compliance_operator/v1` |
| `voting_operator` | `lean-tee/voting_operator/v1` |
| `onboarding_operator` | `lean-tee/onboarding_operator/v1` |
| `trade_operator` | `lean-tee/trade_operator/v1` |

Registry file: [`config/guests/registry.json`](../config/guests/registry.json) (`LEAN_TEE_GUESTS_FILE`).

## Guarantees by profile

| | `lean-tee-v1` | `lean-tee-v2` |
| --- | --- | --- |
| `resultHash` binding | Yes | Yes |
| Proof | Deterministic mock digest | SP1 Hypercube proof commitment |
| Suitable for | CI, demos, cheap reject | **Production integrity** (default for enterprise) |
| Confidentiality | No | No |

## Enterprise packaging

See [ENTERPRISE.md](ENTERPRISE.md) and [SLA.md](SLA.md): mTLS (proxy), tenant ACL, API keys, audit JSONL, quotas, metrics, durable job store. Mock prove remains **CI/dev only**.

## Non-goals

- Nitro / SEV / TDX / sealed confidentiality (see [VS_NITRO.md](VS_NITRO.md))
- Uploading Lean *source* or arbitrary ELF/Wasm to compile on RISC-V (see [GUEST_PROG.md](GUEST_PROG.md) for Lean-**specified** GuestProg payloads)
- Embedding lean-grpc into consumer Lake graphs (call over the wire or use `lean_tee_receipt`)
- Full sail-riscv-lean / sp1-lean end-to-end formalization in v1.0
- Guaranteed delivery if the prover host censors (see [SLA.md](SLA.md))

## Consumers

1. **Direct** — `teeServer` + clients (`teeClient`, Python, Rust)
2. **Library** — depend on `lean_tee_receipt` for hash/mock verify without running Lean
3. **Anchor Strict** — RegisterCompliance fields map to receipt hex; multi-guest measurements (see [ANCHOR_MULTI_GUEST.md](ANCHOR_MULTI_GUEST.md))

## Versioning

- Package / crates: semver (`0.1.0` → `0.2.0` shared crate → `1.0.0` when v2 verify is non-trusting)
- Wire profile strings: `lean-tee-v1` / `lean-tee-v2` (breaking prove semantics bump the profile, not silent)
- Proto package remains `lean_tee.v1` until a wire-incompatible proto change

## lean-grpc pin

Require sibling checkout at **https://github.com/RileyBetts/lean-grpc/tree/v1.0.0** as `../lean-grpc`. GitHub Actions checks out that tag beside this repo.

## Roadmap (integrity multi-guest)

1. Declarative guest registry + four first-party operators
2. Enterprise control plane (ACL, audit, quotas, mTLS docs)
3. Production `lean-tee-v2` prove default + durable jobs
4. SDK `guest_id` + Anchor multi-guest packs
