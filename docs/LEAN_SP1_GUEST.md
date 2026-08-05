# Lean-compiled SP1 guest

## Goal

Measured SP1 guest ELF produced from **Lean → C → RISC-V**, not a Rust semantic twin.
SP1 is retained for the Lean-oriented prover formalization track (`sp1-lean`).

Plan: see [lean-sp1-guest-plan.html](lean-sp1-guest-plan.html).  
Plain-English how the proof works: [sp1-integrity-crib-sheet.html](sp1-integrity-crib-sheet.html).

## Phase 0 (landed spike)

| Piece | Path |
| --- | --- |
| Lean source | [`LeanTee/Sp1Spike.lean`](../LeanTee/Sp1Spike.lean) |
| Lean→C sync | [`scripts/sp1_lean_spike_sync.sh`](../scripts/sp1_lean_spike_sync.sh) |
| C in guest | [`host/guest_lean_spike/c/lean_sp1_spike.c`](../host/guest_lean_spike/c/lean_sp1_spike.c) |
| SP1 guest crate | [`host/guest_lean_spike`](../host/guest_lean_spike) |
| Smoke | `sp1_lean_spike_smoke` (execute-only) |

Prerequisite: SP1 with the RISC-V C toolchain (`sp1up --c-toolchain`):

```bash
export PATH="$HOME/.sp1/bin:$PATH"
export CC_riscv64im_succinct_zkvm_elf="${CC_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/riscv/bin/riscv64-unknown-elf-gcc}"
```

## Phase 1–3 — compliance, GuestProg, cutover

| Piece | Path |
| --- | --- |
| Pure Lean entry | [`LeanTee/GuestSp1.lean`](../LeanTee/GuestSp1.lean) (`lean_tee_guest_run`) |
| GuestProg | [`LeanTee/GuestProg.lean`](../LeanTee/GuestProg.lean) |
| Portable SHA-256 | [`native/sha256_portable.c`](../native/sha256_portable.c) |
| Runtime overlays | [`host/lean_sp1_runtime/`](../host/lean_sp1_runtime/) |
| Minimal Init | [`host/lean_sp1_init_min/`](../host/lean_sp1_init_min/) + `scripts/sp1_lean_guest_build.sh` |
| Measured guest | [`host/guest_lean/`](../host/guest_lean/) (`lean_tee_guest_lean`) |
| CI smoke | `sp1_smoke` (compliance + GuestProg) |

```bash
bash scripts/sp1_lean_runtime_fetch.sh
bash scripts/sp1_lean_runtime_build.sh
bash scripts/sp1_lean_guest_build.sh
cd host
cargo build -p lean_tee_prove_server --release --features sp1 --bin sp1_smoke
SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only
SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0   # gated; OOM-safe
# or: bash scripts/sp1_execute_ci.sh
```

### Verified

- Host Lake GuestSp1 + Init subset + portable SHA.
- SP1 execute: compliance + GuestProg via `sp1_smoke` / dedicated lean smokes.
- Phase 3: Prove server measures Lean ELF; `code_id`s use `…/lean-sp1/v1`.
- Phase 4a: `sp1_smoke` is the CI entry; Lean 4.32.1 + C toolchain required in `sp1-execute.yml`.

### Execute baselines (Phase 4a, local)

| Case | Cycles (approx.) |
| --- | --- |
| compliance allow/deny | ~73k–79k |
| GuestProg v1 | ~230k |
| GuestProg v2 allow | ~387k |

Mock prove+verify of case 0 (compliance-allow-yes) OK via `SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0`.

### Measurement note

`codeHash = SHA256(code_id)` identifies the **logical** operator (`compliance_operator`, `guest_prog_runtime`, …). The **executable** identity for SP1 is the proving key / ELF (`lean_tee_guest_lean`).

Wire `Measurement` is **not** extended: counterparties pin the executable via published digests:

| Field | Meaning |
| --- | --- |
| `elf_sha256` | SHA-256 of the `lean_tee_guest_lean` ELF bytes |
| `vk_hash_bytes` / `vk_bytes32` | SP1 verifying-key digest (`HashableKey`) |

Regenerate / publish:

```bash
bash scripts/sp1_guest_digest.sh                  # → artifacts/sp1_guest_digests.json
# or during CI smoke:
# sp1_smoke --execute-only --print-digests --write-digests artifacts/sp1_guest_digests.json
```

CI uploads the same JSON as the `sp1-guest-digests` artifact on `sp1-execute`. Real CPU prove+verify of one Lean-ELF case is **gated** (`workflow_dispatch` → `prove_one` + `prove_heavy`). Do **not** run local `SP1_PROVER=cpu --prove-one` on ≤16 GiB hosts — it can OOM/lock the machine; scripts require ≥10 GiB free or `SP1_PROVE_HEAVY_FORCE=1`.

### SP1 FENCE note

SP1 does not implement RISC-V `FENCE`. Lean 4.32’s `lean_obj_once` inlines a C11 `_Atomic` seq_cst load that emits `fence`. LEAN_SP1 patches demote `lean_once_cell_t` to plain `int` and make `*_once_cold` fence-free.

## Phase 4b — Init allow-list RFC

Policy: [`docs/LEAN_SP1_INIT_RFC.md`](LEAN_SP1_INIT_RFC.md).

**Decision (this revision):** Lean shims in GuestProg (`joinSep` / `parseNatDec?` / `natToDec`) cover the measured surface; **no new Init modules** admitted. Growth requires the RFC admission checklist (demand, ISA/fence check, smoke, cycle/size budgets). Soft/hard size checks live in `scripts/sp1_lean_guest_build.sh`.

## Non-goals (yet)

- Full Lean kernel / elaborator in SP1
- Switching to RISC0
