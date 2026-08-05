# Public release review scorecard (2026-08-05)

Gate checklist before flipping [RileyBetts/lean-tee](https://github.com/RileyBetts/lean-tee) public.

## Gate 1 — Crypto / integrity

| Check | Result | Notes |
| --- | --- | --- |
| Mock never sold as prod | **Pass** | README / PRODUCT / GETTING_STARTED mark `lean-tee-v1` CI-only |
| Fail-closed v2 | **Pass** | [`LeanTee/ServerMain.lean`](../LeanTee/ServerMain.lean) refuses start without `LEAN_TEE_PROVE_ADDR` unless `ALLOW_MOCK_V2` |
| Accept trust | **Pass** | [`LeanTee/Services.lean`](../LeanTee/Services.lean) SP1 Accept requires issued receipt or `TRUST_PROOF_OK` |
| Digest pin story | **Pass** | [`artifacts/sp1_guest_digests.json`](../artifacts/sp1_guest_digests.json) + THREAT_MODEL / ANCHOR docs |
| Confidentiality honesty | **Pass** | VS_NITRO + CONFIDENTIALITY; `local` incompatible with v2 |
| Dangerous envs | **Pass** | GETTING_STARTED labels `ALLOW_MOCK_V2` / `TRUST_PROOF_OK` unsafe for prod |
| SECURITY scope | **Pass** | Matches threat model; out-of-scope host secrecy |

## Gate 2 — Docs / positioning

| Check | Result | Notes |
| --- | --- | --- |
| Integrity + non-confidentiality pitch | **Pass** | README first screen preserved |
| lean-grpc public pin | **Pass** | Lake `@ v1.0.0`; sibling checkout optional |
| Product-first doc path | **Pass** | GETTING_STARTED next-reading ordered; RFCs under [`docs/rfcs/`](rfcs/) |
| `trade_operator` registry | **Fix applied** | Added to [`config/guests/registry.json`](../config/guests/registry.json) |

## Gate 3 — OSS hygiene

| Check | Result | Notes |
| --- | --- | --- |
| Security contact email | **Fix applied** | `info@rileybetts.ai` in SECURITY.md |
| CODE_OF_CONDUCT | **Fix applied** | Contributor Covenant 2.1 + links |
| Issue / PR templates | **Fix applied** | `.github/ISSUE_TEMPLATE/`, PR template |
| CODEOWNERS / Dependabot | **Fix applied** | Optional polish landed |
| Secret scrub | **Pass** | No private keys/tokens found; `.env` gitignored |
| `main` / `v1.0.0` | **Pass** | Default branch `main`; CI green on latest `main`. Tag `v1.0.0` is one CI-fix commit behind HEAD (expected). |

## Gate 4 — Supply chain / licenses

| Check | Result | Notes |
| --- | --- | --- |
| Apache-2.0 + NOTICE | **Pass** | LICENSE, NOTICE (SP1 MIT OR Apache-2.0; Lean Apache-2.0) |
| lean_sp1_runtime overlays | **Pass** | First-party shims SPDX Apache-2.0; stock Lean fetched/patched at build |
| Mock CI without org secrets | **Pass** | [`ci.yml`](../.github/workflows/ci.yml) uses public actions only |
| SP1 digest pin | **Pass** | Latest `sp1-execute` on `main` succeeded; digests published |

## Gate 5 — Go-live

| Step | Status |
| --- | --- |
| Land hygiene fixes on `main` | Pending push/merge |
| Enable private vulnerability reporting | Pending (GitHub settings) |
| Set visibility public | Pending |
| Fresh-clone verify | Pending after public |
| Release note / Reservoir watch | Pending after public |

## Deferred (honest roadmap)

- Formal verification of SP1 / host
- Folding ELF/vk digests into wire `Measurement`
- PyPI package for Python client
