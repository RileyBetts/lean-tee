# Security policy

## Supported versions

| Version / branch | Supported |
| --- | --- |
| Latest `main` and release tags | Yes |
| Older tags | Best-effort |

Security fixes land on `main` first; maintainers may backport critical fixes to recent tags on a case-by-case basis.

## Reporting a vulnerability

**Please do not open public GitHub issues for exploitable security bugs.**

Report privately by one of:

1. **GitHub Security Advisories** — [Open a private advisory](https://github.com/RileyBetts/lean-tee/security/advisories/new) on this repository (preferred once the repo is public).
2. **Email** — contact the maintainers at the address listed on the GitHub org/profile for Riley Betts Ltd (or the primary maintainer account on the repository).

Include:

- Description and impact
- Steps to reproduce
- Affected commit, tag, or release if known
- Proof-of-concept if available

We aim to acknowledge reports within **5 business days** and will coordinate disclosure timing with you.

## Scope

In scope:

- Receipt forgery, accept/reject bypass, or cross-suite confusion in `LeanTee.TeeReceipt` / `lean_tee_receipt`
- gRPC `Execute` / `AcceptReceipt` / `Prove` handling in `teeServer` and `prove_server`
- ACL, API key, or tenant isolation bugs in the control plane
- Secret leakage when `LEAN_TEE_CONFIDENTIALITY=local` is enabled

Out of scope (by design — see [docs/VS_NITRO.md](docs/VS_NITRO.md)):

- Host OS root reading guest memory
- SP1 proving machine seeing public inputs/outputs
- Mock prove (`lean-tee-v1`) used as production attestation

Upstream **SP1 / Succinct** prover issues should be reported to [succinctlabs/sp1](https://github.com/succinctlabs/sp1) unless lean-tee glue code is clearly at fault.

## Safe harbor

We appreciate responsible disclosure and will not pursue legal action against researchers who follow this policy in good faith.
