# lean-tee

**Portable integrity TEE compute for open systems** — measured guests, hashed receipts, and lean-grpc APIs so anyone can accept honest public results or cheaply reject forged ones — without AWS Nitro, sealed memory, or a cloud PKI root of trust.

> **Not a confidentiality enclave.** lean-tee does **not** hide secrets from the host. It replaces Nitro’s *“prove this code ran on this I/O”* role for **public** workloads; it does **not** replace Nitro’s *“keep keys/data sealed”* role. Full matrix: **[docs/VS_NITRO.md](docs/VS_NITRO.md)**.

| Profile | Prove | Verify | Use |
| --- | --- | --- | --- |
| **`lean-tee-v1`** | Mock proof | Recompute resultHash + mock | CI, demos only |
| **`lean-tee-v2`** | SP1 Hypercube RISC-V | Host verifies SP1; never trust client `proof_ok` alone | **Production integrity** |

**First-party guests:** `compliance_operator`, `voting_operator`, `onboarding_operator`, `trade_operator` ([registry](config/guests/registry.json)).

## Why open source this?

- **Portable attestation** — verify on CI, another cloud, or a chain without embedding AWS PCR/NSM trust.
- **Cheap reject** — forged receipts fail Accept; goldens + adversarial demos gate the algorithms.
- **Spec-first** — Lean checkers + Rust `lean_tee_receipt` twin; wire proto is normative.
- **Multi-guest enterprise shape** — ACL, audit, quotas, durable jobs ([ENTERPRISE.md](docs/ENTERPRISE.md)) without pretending to be Nitro.

## Nitro in one glance

| Need | Use |
| --- | --- |
| Integrity of public compute + multi-party verify | **lean-tee** |
| Sealed secrets / KMS release to enclave PCRs | **AWS Nitro** (or similar confidential TEE) |
| Both | Compose: confidential TEE for secrets + lean-tee for public receipts |

## Quickstart (mock, no SP1)

Requires Lean 4 (`lean-toolchain`), OpenSSL, and a [lean-grpc](https://github.com/RileyBetts/lean-grpc) checkout (git-pinned; see below).

```bash
lake build receiptTests teeServer teeClient teeLoopback
./.lake/build/bin/receiptTests
./scripts/standalone_demo.sh
./scripts/adversarial_matrix_demo.sh
./scripts/action_matrix_demo.sh
./scripts/enterprise_control_demo.sh
./scripts/cross_impl_golden_demo.sh
./scripts/guest_prog_demo.sh
```

Manual:

```bash
./.lake/build/bin/teeServer          # LEAN_TEE_PORT=50071
echo 'rules=vote.yes,vote.no' > /tmp/rules.txt
./.lake/build/bin/teeClient 127.0.0.1:50071 vote.yes /tmp/rules.txt
```

Rust Prove (mock, no `cargo prove`):

```bash
cd host && cargo build -p lean_tee_prove_server --no-default-features
LEAN_TEE_PROVE_MODE=mock LEAN_TEE_PROVE_PORT=50072 \
  ./target/debug/prove_server
```

## Product contract (`lean-tee-v1`)

- Wire: [`proto/lean_tee/v1/tee.proto`](proto/lean_tee/v1/tee.proto)
- `resultHash` domain: `lean-tee/v1` (length-prefixed SHA-256)
- Mock `proof_ref` domain: `lean-tee/mock-proof/v1`
- Default guest: `SHA256("lean-tee/compliance_operator/v1")` (empty `guest_id`)
- Shared Rust algorithms: crate `lean_tee_receipt` under [`host/receipt`](host/receipt)

Docs: [PRODUCT](docs/PRODUCT.md) · [GUEST_PROG](docs/GUEST_PROG.md) · [VS_NITRO](docs/VS_NITRO.md) · [API](docs/API.md) · [THREAT_MODEL](docs/THREAT_MODEL.md) · [CRYPTO](docs/CRYPTO.md) · [ENTERPRISE](docs/ENTERPRISE.md) · [SLA](docs/SLA.md)

## Layout

| Path | Role |
| --- | --- |
| `LeanTee/` | Spec: hash, receipts, guests, control plane, gRPC services |
| `proto/lean_tee/v1/` | Normative `.proto` |
| `host/receipt` | Shared Rust receipt crypto (Anchor-linkable) |
| `host/compliance_lib` | Multi-guest operator logic |
| `host/prove_server` | tonic Prove (mock and/or SP1) |
| `host/guest` | SP1 RISC-V guest ELF |
| `clients/python` | Python Execute / AcceptReceipt SDK |
| `clients/rust` | Thin tonic Tee + Prove client |
| `config/guests/` | First-party guest registry |
| `Tests/` | Receipt + guest registry + gRPC loopbacks |
| `docs/` | Product, Nitro comparison, API, threat, CRYPTO, ENTERPRISE, SLA |
| `scripts/*_demo.sh` | Standalone, adversarial, action, enterprise, golden, prove loopback |

## Dependencies

- [lean-grpc](https://github.com/RileyBetts/lean-grpc) **v1.0.0** as sibling `../lean-grpc` (CI checks out that tag; see [docs/PRODUCT.md](docs/PRODUCT.md))
- OpenSSL (`libssl-dev`, `pkg-config`)
- Optional: SP1 toolchain (`sp1up`) for `lean-tee-v2` / `--features sp1`

## Status

- [x] Receipt hashing + `acceptReceipt`
- [x] lean-grpc Tee / Prove / Verify / AnchorSink
- [x] Shared `lean_tee_receipt` + golden vectors
- [x] Mock-first standalone demo + CI
- [x] Multi-guest registry (compliance / voting / onboarding / trade)
- [x] Enterprise control plane (ACL, audit, quotas, job dir, mTLS docs)
- [x] SP1 prove path + host verify (`lean-tee-v2`); production default documented
- [x] Anchor Chain Strict Mode consumer + multi-guest mapping docs

## License

Apache-2.0 — see [LICENSE](LICENSE).
