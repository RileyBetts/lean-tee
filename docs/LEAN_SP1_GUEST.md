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

Phase 0 uses **UInt32-only** Lean exports **without** full `Init` runtime initialization (same idea as Anoma’s lightweight RISC0 Lean example). That is enough to prove the compile/link/execute pipeline; compliance/`ByteArray` need the runtime workstream next.

## Later phases

1. Minimal Lean runtime for SP1 (allocator, RC, ByteArray, …)
2. Lean compliance oracle in guest
3. Lean GuestProg in guest
4. Retire Rust twin as measured guest; new `code_id`s

## Non-goals (yet)

- Full Lean kernel / elaborator in SP1
- Switching to RISC0
