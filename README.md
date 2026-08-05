# lean-tee

## In plain English

**Prove that a public decision was made by the rules you published — without asking anyone to trust your server, and without locking into AWS Nitro.**

Imagine a compliance check, a vote, or a trade gate: someone submits an action, your policy program runs, and you get a yes/no (or richer) result. With lean-tee, that run produces a **receipt**: a small package that says *which program* ran, *what inputs* it saw, and *what it output*. Others — another team, a chain, a regulator, CI — can **check the receipt** and accept an honest result or reject a forged one. They do not need your cloud account or a sealed hardware box.

**How SP1 fits in.** The production path runs that policy program inside [SP1](https://github.com/succinctlabs/sp1), a *zkVM* (think: a special computer that can prove what it executed). SP1 produces a cryptographic proof that *this exact guest program* saw *these inputs* and produced *this output*. lean-tee wraps that into a stable receipt and API. Checking the proof is much cheaper than trusting the operator — and cheaper than re-running everything yourself when you only need to know the result is real.

**Lean 4 on SP1.** Beyond wrapping SP1, this repo adds a **Lean 4 toolchain path into the zkVM**: we port a Lean 4.32.1 runtime and compile measured guests Lean → C → RISC-V so the program that SP1 proves can be written and specified in Lean—not only as a Rust twin. Details: [docs/LEAN_SP1_GUEST.md](docs/LEAN_SP1_GUEST.md).

**What this is not.** lean-tee does **not** hide secrets from the machine that runs it. If you need sealed keys or private data the host must never see, use a confidential enclave (e.g. AWS Nitro) for that part, and lean-tee for public, verifiable outcomes. More below and in [docs/VS_NITRO.md](docs/VS_NITRO.md).

---

## For builders

**Portable integrity TEE compute for open systems** — measured guests, hashed receipts, and lean-grpc APIs so anyone can accept honest public results or cheaply reject forged ones — without AWS Nitro, sealed memory, or a cloud PKI root of trust.

> **Not a confidentiality enclave.** lean-tee does **not** hide secrets from the host. It replaces Nitro’s *“prove this code ran on this I/O”* role for **public** workloads; it does **not** replace Nitro’s *“keep keys/data sealed”* role. Full matrix: **[docs/VS_NITRO.md](docs/VS_NITRO.md)**.

| Profile | Prove | Verify | Use |
| --- | --- | --- | --- |
| **`lean-tee-v2`** | SP1 Hypercube RISC-V | Host verifies SP1; never trust client `proof_ok` alone | **Production integrity (default)** |
| **`lean-tee-v1`** | Mock proof | Recompute resultHash + mock | **CI / demos only — never prod** |

Set `LEAN_TEE_DEFAULT_PROFILE=lean-tee-v2` and wire `LEAN_TEE_PROVE_ADDR` to an SP1 `prove_server`. Mock must not be the hero or production path.

**First-party guests:** `compliance_operator`, `voting_operator`, `onboarding_operator`, `trade_operator` ([registry](config/guests/registry.json)). Lean-specified programs: [GUEST_PROG.md](docs/GUEST_PROG.md).

## Why open source this?

- **Portable attestation** — verify on CI, another cloud, or a chain without embedding AWS PCR/NSM trust.
- **Cheap reject** — forged receipts fail Accept; goldens + adversarial demos gate the algorithms.
- **Spec-first** — Lean checkers + Rust `lean_tee_receipt` twin; wire proto is normative.
- **Lean 4 toolchain on SP1** — measured guest is Lean-compiled (runtime port + Init allow-list); SP1 proves that Lean guest, not a hand-written substitute.
- **Multi-guest enterprise shape** — ACL, audit, quotas, durable jobs ([ENTERPRISE.md](docs/ENTERPRISE.md)) without pretending to be Nitro.

## Nitro in one glance

| Need | Use |
| --- | --- |
| Integrity of public compute + multi-party verify | **lean-tee** |
| Sealed secrets / KMS release to enclave PCRs | **AWS Nitro** (or similar confidential TEE) |
| Both | Compose: confidential TEE for secrets + lean-tee for public receipts |

## Quickstart (mock — CI/demo only)

Requires Lean 4 (`lean-toolchain`), OpenSSL, and `lake update` (pulls [lean-grpc](https://github.com/RileyBetts/lean-grpc) v1.1.0).

**This path uses `lean-tee-v1` mock prove. Do not treat it as production attestation.**

Full setup: **[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)**.

```bash
lake build receiptTests teeServer teeClient teeLoopback
./.lake/build/bin/receiptTests
./scripts/standalone_demo.sh
./scripts/adversarial_matrix_demo.sh
./scripts/action_matrix_demo.sh
./scripts/enterprise_control_demo.sh
./scripts/cross_impl_golden_demo.sh
./scripts/guest_prog_demo.sh
./scripts/confidentiality_local_demo.sh
```

## Production path (`lean-tee-v2`)

Measured guest = **Lean 4 → C → SP1 RISC-V** (`host/guest_lean` + `host/lean_sp1_runtime/`). See [LEAN_SP1_GUEST.md](docs/LEAN_SP1_GUEST.md).

1. Install SP1 (`sp1up`, including `--c-toolchain`) and build host with `--features sp1`.
2. Run `prove_server` (CPU/network prover) and point `teeServer` at it:

```bash
# execute-only smoke (CI/nightly gate — no heavy prove by default)
bash scripts/sp1_execute_ci.sh

# careful local staged tests
bash scripts/sp1_test_careful.sh
```

3. Server: `LEAN_TEE_DEFAULT_PROFILE=lean-tee-v2` + `LEAN_TEE_PROVE_ADDR=host:port` (never ship mock as the default).

Manual mock server (dev):

```bash
./.lake/build/bin/teeServer          # LEAN_TEE_PORT=50071
echo 'rules=vote.yes,vote.no' > /tmp/rules.txt
./.lake/build/bin/teeClient 127.0.0.1:50071 vote.yes /tmp/rules.txt
```

Rust Prove (mock, no `cargo prove`) — **CI/dev only**:

```bash
cd host && cargo build -p lean_tee_prove_server --no-default-features
LEAN_TEE_PROVE_MODE=mock LEAN_TEE_PROVE_PORT=50072 \
  ./target/debug/prove_server
```

## Product contract (`lean-tee-v1` / `lean-tee-v2`)

- Wire: [`proto/lean_tee/v1/tee.proto`](proto/lean_tee/v1/tee.proto)
- `resultHash` domain: `lean-tee/v1` (length-prefixed SHA-256)
- Mock `proof_ref` domain: `lean-tee/mock-proof/v1` (**not** production)
- Default guest: `SHA256("lean-tee/compliance_operator/lean-sp1/v1")` (empty `guest_id`)
- Shared Rust algorithms: crate `lean_tee_receipt` under [`host/receipt`](host/receipt)
- Production prove: SP1 Hypercube via `lean-tee-v2` + host verify

Docs: [GETTING_STARTED](docs/GETTING_STARTED.md) · [PRODUCT](docs/PRODUCT.md) · [THREAT_MODEL](docs/THREAT_MODEL.md) · [CRYPTO](docs/CRYPTO.md) · [LEAN_SP1_GUEST](docs/LEAN_SP1_GUEST.md) · [GUEST_PROG](docs/GUEST_PROG.md) · [CONFIDENTIALITY](docs/CONFIDENTIALITY.md) · [VS_NITRO](docs/VS_NITRO.md) · [API](docs/API.md) · [ENTERPRISE](docs/ENTERPRISE.md) · [SLA](docs/SLA.md)

## Layout

| Path | Role |
| --- | --- |
| `LeanTee/` | Spec: hash, receipts, guests, control plane, gRPC services |
| `proto/lean_tee/v1/` | Normative `.proto` |
| `host/receipt` | Shared Rust receipt crypto (Anchor-linkable) |
| `host/compliance_lib` | Multi-guest operator logic |
| `host/prove_server` | tonic Prove (mock and/or SP1) |
| `host/guest_lean` | Measured SP1 guest ELF (Lean→C→RISC-V) |
| `host/lean_sp1_runtime/` | Lean 4.32.1 runtime overlays / shims for SP1 |
| `host/lean_sp1_init_min/` | Minimal Init for the Lean guest |
| `host/guest` | Legacy Rust twin (optional differential) |
| `artifacts/sp1_guest_digests.json` | Published ELF / verifying-key digests |
| `clients/python` | Python Execute / AcceptReceipt SDK |
| `clients/rust` | Thin tonic Tee + Prove client |
| `config/guests/` | First-party guest registry |
| `Tests/` | Receipt + guest registry + gRPC loopbacks |
| `docs/` | Product, Nitro, API, threat, SP1 guest guide / crib sheet |
| `scripts/sp1_*.sh` | SP1 runtime/guest build, CI smoke, digests |
| `scripts/*_demo.sh` | Standalone, adversarial, action, enterprise, golden, prove loopback |

SP1 ownership split (Lean guest + glue vs upstream prover): [docs/LEAN_SP1_GUEST.md](docs/LEAN_SP1_GUEST.md#ownership-what-this-repo-contributes-vs-sp1).

## Dependencies

- [lean-grpc](https://github.com/RileyBetts/lean-grpc) **v1.1.0** — fetched by `lake update` (git pin in [`lakefile.lean`](lakefile.lean); see [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md))
- OpenSSL (`libssl-dev`, `pkg-config`)
- Optional: [SP1](https://github.com/succinctlabs/sp1) toolchain (`sp1up`) for `lean-tee-v2` / `--features sp1` (upstream **MIT OR Apache-2.0**)

## Community

- [Getting started](docs/GETTING_STARTED.md) · [Contributing](CONTRIBUTING.md) · [Code of conduct](CODE_OF_CONDUCT.md) · [Security](SECURITY.md)
- [Public release review scorecard](docs/RELEASE_REVIEW.md)

## Status

- [x] Receipt hashing + `acceptReceipt`
- [x] lean-grpc Tee / Prove / Verify / AnchorSink
- [x] Shared `lean_tee_receipt` + golden vectors
- [x] Mock-first standalone demo + CI
- [x] Multi-guest registry (compliance / voting / onboarding / trade)
- [x] Enterprise control plane (ACL, audit, quotas, job dir, mTLS docs)
- [x] SP1 prove path + host verify (`lean-tee-v2`); production default + gated execute CI
- [x] Lean-compiled measured guest + runtime port / FENCE patches + Init allow-list
- [x] GuestProg v1/v2 + LoadProgram ACL / size limits
- [x] Optional local confidentiality (`confidentiality=local` sealed worker; not Nitro)
- [x] Anchor Chain Strict Mode consumer + multi-guest mapping docs
- [x] Published ELF/vk digests + SP1 integrity crib sheet

## License

Apache-2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
First-party lean-tee code is Apache-2.0. Upstream SP1 is dual-licensed MIT OR Apache-2.0; we depend on it under its Apache-2.0 option.