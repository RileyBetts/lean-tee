# Changelog

## Unreleased

- Pin lean-grpc dependency to **v1.1.0** (was v1.0.0)
- Mid-tier Lean SP1 guest + `sp1_lean_mid_smoke --prove` (Init-free mix/rounds; laptop-oriented)
- Spike smoke: optional `--prove` for CPU prove+verify


## 1.0.1 — 2026-08-05

Patch release: CI fixes + package metadata aligned to tag `v1.0.1`.

### Fixes

- Rust client fills new Execute / Measure / Prove proto fields (unblocks `rust-mock` CI)
- `lean-mock` CI installs Lean via elan at repo root (fixes broken lean-action checkout path)

### Public release hygiene

- Add `trade_operator` to `config/guests/registry.json` (aligned with Lean/Rust builtins)
- Security contact email, Contributor Covenant CoC, issue/PR templates, Dependabot, CODEOWNERS
- Move Init RFC + guest plan HTML under `docs/rfcs/`; product-first doc reading order
- Document unsafe prod env vars (`ALLOW_MOCK_V2`, `TRUST_PROOF_OK`); release review scorecard
- Package versions: Lake `1.0.1`, host workspace `1.0.1`, Rust client `1.0.1`

## 1.0.0 — 2026-08-05

First stable release: Lean-measured SP1 guest, integrity-hardened Accept path, adopter docs, and plain-English README pitch.

### Integrity

- SP1 guest ABI binds `codeHash` (+ optional rules); multi-guest surfaces enforced in-guest
- Receipts stamp real `crypto_suite` (`sha256+mock` / `sha256+sp1`); fail-closed v2 without Prove; Accept for SP1 requires issued receipt (or explicit trust env)
- Published ELF/vk digests + CI pin check (`artifacts/sp1_guest_digests.json`, `sp1-execute`)

### Stretch — ELF/vk digests + gated CPU prove

- Publish `elf_sha256` / `vk_*` for `lean_tee_guest_lean` via `sp1_smoke --print-digests` / `scripts/sp1_guest_digest.sh` → `artifacts/sp1_guest_digests.json` (CI artifact on `sp1-execute`).
- Anchor Strict / multi-guest docs: counterparties pin digests; wire `Measurement` unchanged (`codeHash`+`configHash`).
- Real CPU prove+verify of one Lean-ELF case gated by `workflow_dispatch` `prove_heavy` (+ `prove_one`). Local `SP1_PROVE_HEAVY=1` aborts unless ≥10 GiB `MemAvailable` or `SP1_PROVE_HEAVY_FORCE=1` (CPU prove can hard-lock 16 GiB laptops).
- Docs: ownership split (lean-tee guest/glue vs upstream SP1) in `LEAN_SP1_GUEST.md` / README; full Apache-2.0 `LICENSE` + `NOTICE` (SP1 is MIT OR Apache-2.0; first-party code Apache-2.0).

### Phase 4b — Init allow-list RFC

- [`docs/rfcs/LEAN_SP1_INIT_RFC.md`](docs/rfcs/LEAN_SP1_INIT_RFC.md): allow-list, FENCE/init traps, admission rule, cycle/size budgets.
- Decision: current GuestProg Lean shims suffice; no new Init modules. Guest build script enforces hard archive size cap (6 MiB).

### Phase 4a — Lean guest hardening

- `sp1_smoke` covers compliance **and** GuestProg on `lean_tee_guest_lean` (CI entry).
- SP1 CI pins Lean **4.32.1**, requires `sp1up --c-toolchain`, optional mock `--prove-one`.
- `codeHash` remains `SHA256(code_id)`; ELF identity is SP1 vk/ELF (digests published beside measurement, not folded into `codeHash`).

### Breaking — Lean SP1 guest cutover (Phase 3)

- **Measured SP1 ELF** is now Lean-compiled (`lean_tee_guest_lean` / `host/guest_lean`), not the Rust twin (`host/guest`).
- **`code_id` strings** bumped to `lean-tee/<guest>/lean-sp1/v1` (e.g. `lean-tee/compliance_operator/lean-sp1/v1`, `lean-tee/guest_prog_runtime/lean-sp1/v1`). Recompute Strict / Anchor allow-lists from the new `codeHash = SHA256(code_id)`.
- Rust guest crate kept for optional differential builds (`LEAN_TEE_BUILD_RUST_GUEST=1`); not linked into Prove by default.

### Other

- Optional `LEAN_TEE_CONFIDENTIALITY=local` sealed worker (secrets out of PublicIO; not Nitro)
- Production default profile `lean-tee-v2`; mock called out as CI-only; weekly/manual SP1 execute CI (`sp1-execute.yml`, `scripts/sp1_execute_ci.sh`)
- GuestProg v1/v2 on the Lean SP1 guest (execute-only smokes)
- Adopter docs: CONTRIBUTING, SECURITY, GETTING_STARTED; lean-grpc git pin; README plain-English intro
- Marketing docs vs Nitro ([VS_NITRO.md](docs/VS_NITRO.md)); multi-guest enterprise packaging; crypto suites; demos
- Package versions: Lake `1.0.0`, host workspace `1.0.0`, Rust client `1.0.0`

## 0.1.0 — 2026-08-02

- Initial product spine: Lean Tee/Prove/Verify/AnchorSink, mock proofs, teeServer/teeClient
- Host compliance lib + SP1-ready prove_server
- Product docs, `lean_tee_receipt`, standalone demo, CI, clients, policy/registry, SP1 host verify path
- Profiles: `lean-tee-v1` (mock), `lean-tee-v2` (SP1)
