# lean-tee vs AWS Nitro Enclaves

Honest comparison for open-source adopters and architects. **lean-tee is not a Nitro clone.** It replaces *some* Nitro *roles* and deliberately does not replace others.

## One-sentence pitch

**lean-tee** gives you **portable, measurable integrity** for public workloads (hashed receipts + optional zk proofs) that any verifier or chain can check — without AWS silicon, Nitro PKI, or sealed memory.

**AWS Nitro Enclaves** give you **confidential isolated compute** on EC2 — secrets stay inside the enclave; attestation is rooted in AWS hardware and IAM/KMS.

## Role matrix

| Role people use Nitro for | lean-tee? | Notes |
| --- | --- | --- |
| Prove “this measured code ran on these inputs → these outputs” | **Yes (core)** | `TeeReceipt` + `resultHash` + prove/verify |
| Cheap reject of forged / tampered evidence | **Yes (core)** | Fail-closed Accept; adversarial demos |
| Attestation usable outside AWS (multi-cloud, laptop, CI, L1/L2) | **Yes** | No AWS PCR / NSM root of trust |
| Multi-party / chain “Strict Mode” compliance gates | **Yes** | Designed for public I/O + Anchor-style sinks |
| Policy / guest allow-lists (voting, onboarding, trade, …) | **Yes** | First-party multi-guest registry |
| Enterprise packaging (mTLS proxy, ACL, audit, quotas) | **Partial** | Documented control plane; you operate it |
| Decrypt secrets / hold private keys inside the boundary | **No** | No sealed memory |
| KMS “release key only to PCR snapshot” | **No** | Use Nitro (or similar) for that |
| Protect PII / confidential ML weights from the host OS | **No** | Host can see public I/O by design |
| Isolate an arbitrary container/VM from the parent instance | **No** | Not a hypervisor enclave |
| Drop-in replacement for `nitro-cli` / NSM API apps | **No** | Different API (`lean_tee.v1` gRPC) |

## Where lean-tee can replace Nitro

Use lean-tee instead of Nitro when the job is **integrity of public computation**, not secrecy:

1. **Cross-org evidence** — Counterparties must verify a compliance/vote/trade decision without trusting your AWS account.
2. **Chain / rollup / agent ledgers** — Attestation must verify offline or on-chain without embedding AWS PKI.
3. **Multi-cloud or air-gapped verify** — Same receipt format on CI, bare metal, or another cloud.
4. **Cheap reject path** — Adversarial nodes forge outputs; verifiers recompute hash/proof in milliseconds (mock) or via host-verified SP1 (v2).
5. **Spec-first operators** — You want named measured guests (`voting_operator`, …) and Lean/Rust goldens, not a general enclave VM.

In those roles, Nitro is often the *wrong* tool: attestation stays AWS-centric, and confidentiality is unused cost if inputs/outputs are public anyway.

## Where lean-tee cannot replace Nitro

Keep Nitro (or SEV-SNP / TDX / similar) when you need:

1. **Confidentiality** — Secrets, keys, regulated data must not be visible to the host OS or cloud admin.
2. **Hardware isolation** — Parent EC2 must not read enclave memory.
3. **AWS KMS / IAM enclave attestation** — Key release gated on Nitro measurements.
4. **Lift-and-shift enclave apps** — Existing Nitro SDK / vsock / NSM workflows.
5. **“Run arbitrary code in a sealed box”** — lean-tee ships a **registry of first-party guests**, not BYO sealed VMs.

If you need both secrecy *and* portable public receipts:

- **Hardware sealed RAM** — use Nitro / SEV-SNP / TDX (or similar); lean-tee for the **public attestation surface**.
- **Optional local hygiene** — lean-tee `LEAN_TEE_CONFIDENTIALITY=local` keeps secrets out of receipts via a sealed worker; this is **not** Nitro-equivalent. See [CONFIDENTIALITY.md](CONFIDENTIALITY.md).

## Trust roots (why this matters)

| | Nitro | lean-tee |
| --- | --- | --- |
| Isolation | AWS Nitro hardware + hypervisor | Process/sandbox + measured guest (no sealed RAM) |
| Attestation root | AWS (PCRs, NSM, IAM) | Hash domains + mock (dev) or SP1 zkVM + host verify (prod) |
| Who can verify | Parties that trust AWS attestation | Anyone who can check the receipt/proof |
| Typical payload | Often secret-bearing | **Public** inputs/outputs by design |

## Profiles (do not oversell mock)

| Profile | Claim |
| --- | --- |
| `lean-tee-v1` (mock) | CI/demo only — deterministic digest, **not** production attestation |
| `lean-tee-v2` (SP1) | Production **integrity** under SP1 + host verify TCB — still **not** confidentiality |
| `confidentiality=local` | Optional process isolation for secrets — **not** hardware TEE ([CONFIDENTIALITY.md](CONFIDENTIALITY.md)) |

## Bottom line

| Question | Answer |
| --- | --- |
| Is lean-tee “open-source Nitro”? | **No.** |
| Can it replace Nitro for **integrity / portable attestation / cheap reject**? | **Yes — that is the product.** |
| Can it replace Nitro for **secrets / KMS / sealed isolation**? | **No — use a real confidential TEE.** |

See also: [PRODUCT.md](PRODUCT.md), [THREAT_MODEL.md](THREAT_MODEL.md), [ENTERPRISE.md](ENTERPRISE.md), [CONFIDENTIALITY.md](CONFIDENTIALITY.md).
