# Lean-compiled SP1 guest (in progress)

## Goal

Measured SP1 guest ELF produced from **Lean → C → RISC-V**, not a Rust semantic twin.
SP1 is retained for the Lean-oriented prover formalization track (`sp1-lean`).

Plan: see [lean-sp1-guest-plan.html](lean-sp1-guest-plan.html) / Cursor plan `lean_sp1_guest_no_rust_twin`.

## Phase 0 (landed spike)

| Piece | Path |
| --- | --- |
| Lean source | [`LeanTee/Sp1Spike.lean`](../LeanTee/Sp1Spike.lean) |
| Lean→C sync | [`scripts/sp1_lean_spike_sync.sh`](../scripts/sp1_lean_spike_sync.sh) |
| C in guest | [`host/guest_lean_spike/c/lean_sp1_spike.c`](../host/guest_lean_spike/c/lean_sp1_spike.c) |
| SP1 guest crate | [`host/guest_lean_spike`](../host/guest_lean_spike) |
| Smoke | `sp1_lean_spike_smoke` (execute-only) |

Prerequisite: SP1 with the RISC-V C toolchain (`sp1up --c-toolchain`), so `cc` can compile guest C for `riscv64im-succinct-zkvm-elf`:

```bash
export PATH="$HOME/.sp1/bin:$PATH"
export CC_riscv64im_succinct_zkvm_elf="${CC_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/bin/riscv64-unknown-elf-gcc}"

bash scripts/sp1_lean_spike_sync.sh
cd host
cargo build -p lean_tee_prove_server --release --features sp1 --bin sp1_lean_spike_smoke
SP1_PROVER=cpu ./target/release/sp1_lean_spike_smoke
# or: CARGO_TARGET_DIR=… ./$CARGO_TARGET_DIR/release/sp1_lean_spike_smoke
```

Phase 0 uses **UInt32-only** Lean exports **without** full `Init` runtime initialization (same idea as Anoma’s lightweight RISC0 Lean example). Verified: `sp1_lean_spike_smoke OK tag=0x4c535031 sum=42`.

## Phase 1–2 — runtime + compliance + GuestProg

| Piece | Path |
| --- | --- |
| Pure Lean entry | [`LeanTee/GuestSp1.lean`](../LeanTee/GuestSp1.lean) (`lean_tee_guest_run`) |
| GuestProg | [`LeanTee/GuestProg.lean`](../LeanTee/GuestProg.lean) (slimmed for SP1 Init) |
| Portable SHA-256 | [`native/sha256_portable.c`](../native/sha256_portable.c) (same ABI as OpenSSL FFI) |
| Runtime overlays | [`host/lean_sp1_runtime/`](../host/lean_sp1_runtime/) |
| Minimal Init | [`host/lean_sp1_init_min/`](../host/lean_sp1_init_min/) + `scripts/sp1_lean_guest_build.sh` |
| SP1 guest crate | [`host/guest_lean/`](../host/guest_lean/) |
| Fetch / build | `scripts/sp1_lean_runtime_{fetch,build}.sh` → `.cache/lean-sp1-runtime/` |

```bash
bash scripts/sp1_lean_runtime_fetch.sh
bash scripts/sp1_lean_runtime_build.sh   # → .cache/lean-sp1-runtime/prefix/lib/libLean.a
bash scripts/sp1_lean_guest_build.sh     # → .cache/lean-sp1-guest/libLeanTeeGuest.a
cd host
cargo build -p lean_tee_prove_server --release --features sp1 \
  --bin sp1_lean_guest_smoke --bin sp1_lean_guestprog_smoke
SP1_PROVER=cpu ./target/release/sp1_lean_guest_smoke
SP1_PROVER=cpu ./target/release/sp1_lean_guestprog_smoke
```

### Verified

- **Host:** Lake GuestSp1 C + Init subset + portable SHA: `decision=allow` for `action=vote.yes`.
- **SP1 compliance (empty program):** `sp1_lean_guest_smoke` matches Rust `run_compliance`.
- **SP1 GuestProg (non-empty program):** `sp1_lean_guestprog_smoke` matches Rust `run_measured` for v1 allow/deny and v2 allow / miss-interaction / deny-wins.

### SP1 FENCE note

SP1 does not implement RISC-V `FENCE`. Lean 4.32’s `lean_obj_once` inlines a C11 `_Atomic` seq_cst load that emits `fence` → `got unimplemented as opcode`. The LEAN_SP1 patches demote `lean_once_cell_t` to plain `int` and make `*_once_cold` fence-free; `scripts/sp1_lean_runtime_build.sh` overlays the patched `lean.h` into the runtime prefix.

Also: GuestProg avoids heavy Init (`String.intercalate` / `Slice`) and uses a real `l_Nat_reprFast` (or `natToDec`) so v2 `max_input_bytes=` hashes match Rust.

Diagnostic bisect helper: [`host/lean_sp1_runtime/once_probe.c`](../host/lean_sp1_runtime/once_probe.c).

Runtime build (Lean **4.32.1**, not Anoma 4.22):

```bash
bash scripts/sp1_lean_runtime_fetch.sh   # sparse-clone + LEAN_SP1 patch
bash scripts/sp1_lean_runtime_build.sh   # → .cache/lean-sp1-runtime/prefix/lib/libLean.a
```


## Later phases

1. Retire Rust twin as measured guest; new `code_id`s
2. Stretch: larger Init / kernel-like surface

## Non-goals (yet)

- Full Lean kernel / elaborator in SP1
- Switching to RISC0
