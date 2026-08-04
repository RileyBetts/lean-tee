# Changelog

## Unreleased

### Phase 4b — Init allow-list RFC

- [`docs/LEAN_SP1_INIT_RFC.md`](docs/LEAN_SP1_INIT_RFC.md): allow-list, FENCE/init traps, admission rule, cycle/size budgets.
- Decision: current GuestProg Lean shims suffice; no new Init modules. Guest build script enforces hard archive size cap (6 MiB).

### Phase 4a — Lean guest hardening

- `sp1_smoke` covers compliance **and** GuestProg on `lean_tee_guest_lean` (CI entry).
- SP1 CI pins Lean **4.32.1**, requires `sp1up --c-toolchain`, optional mock `--prove-one`.
- `codeHash` remains `SHA256(code_id)`; ELF identity is SP1 vk/ELF (not an ELF digest in measurement).

### Breaking — Lean SP1 guest cutover (Phase 3)

- **Measured SP1 ELF** is now Lean-compiled (`lean_tee_guest_lean` / `host/guest_lean`), not the Rust twin (`host/guest`).
- **`code_id` strings** bumped to `lean-tee/<guest>/lean-sp1/v1` (e.g. `lean-tee/compliance_operator/lean-sp1/v1`, `lean-tee/guest_prog_runtime/lean-sp1/v1`). Recompute Strict / Anchor allow-lists from the new `codeHash = SHA256(code_id)`.
- Rust guest crate kept for optional differential builds (`LEAN_TEE_BUILD_RUST_GUEST=1`); not linked into Prove by default.

### Other

- Optional `LEAN_TEE_CONFIDENTIALITY=local` sealed worker (secrets out of PublicIO; not Nitro)
- Production default profile `lean-tee-v2`; mock called out as CI-only; weekly/manual SP1 execute CI (`sp1-execute.yml`, `scripts/sp1_execute_ci.sh`)
- GuestProg v1/v2 on the Lean SP1 guest (execute-only smokes)
- Marketing docs vs Nitro ([VS_NITRO.md](docs/VS_NITRO.md)); multi-guest enterprise packaging; crypto suites; demos

## 0.1.0 — 2026-08-02

- Initial product spine: Lean Tee/Prove/Verify/AnchorSink, mock proofs, teeServer/teeClient
- Host compliance lib + SP1-ready prove_server
- Product docs, `lean_tee_receipt`, standalone demo, CI, clients, policy/registry, SP1 host verify path
- Profiles: `lean-tee-v1` (mock), `lean-tee-v2` (SP1)
