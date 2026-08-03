# Changelog

## Unreleased

- Optional `LEAN_TEE_CONFIDENTIALITY=local` sealed worker (secrets out of PublicIO; not Nitro)
- Production default profile `lean-tee-v2`; mock called out as CI-only; weekly/manual SP1 execute CI (`sp1-execute.yml`, `scripts/sp1_execute_ci.sh`)
- GuestProg v2: `deny=`, `require_interaction`, `max_input_bytes`; program size cap; `load_program` ACL tenants
- GuestProg runtime: Lean-specified programs via gRPC LoadProgram; SP1 RISC-V interpreter path
- Marketing docs vs Nitro ([VS_NITRO.md](docs/VS_NITRO.md)); multi-guest enterprise packaging; crypto suites; demos

## 0.1.0 — 2026-08-02

- Initial product spine: Lean Tee/Prove/Verify/AnchorSink, mock proofs, teeServer/teeClient
- Host compliance lib + SP1-ready prove_server
- Product docs, `lean_tee_receipt`, standalone demo, CI, clients, policy/registry, SP1 host verify path
- Profiles: `lean-tee-v1` (mock), `lean-tee-v2` (SP1)
