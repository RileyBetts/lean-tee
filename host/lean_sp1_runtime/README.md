# Lean SP1 runtime (Lean 4.32.1 → RISC-V)

Compiles a Lean **4.32.1** C++ runtime for SP1’s `riscv64im-succinct-zkvm-elf`.

Anoma’s [lean-risc0-runtime](https://github.com/anoma/lean-risc0-runtime) targets Lean **4.22** and is **not** drop-in (ST-ref ABI diverged). We fetch stock Lean `v4.32.1` `src/runtime` and apply `LEAN_SP1` stubs via `scripts/sp1_lean_runtime_patch.py` (same idea as Anoma’s `LEAN_RISC0`).

## Status

| Step | State |
| --- | --- |
| Fetch Lean `v4.32.1` `src/runtime` + `src/util` | `scripts/sp1_lean_runtime_fetch.sh` |
| Apply `LEAN_SP1` stubs | `scripts/sp1_lean_runtime_patch.py` |
| Compile cores → `libLean.a` | `scripts/sp1_lean_runtime_build.sh` (**works**) |
| Init IR subset for SP1 | `scripts/sp1_lean_guest_build.sh` (**works**) |
| Link GuestSp1 + portable sha256 | `host/guest_lean` (**works**; `sp1_lean_guest_smoke` execute-only OK) |

## Prerequisites

```bash
sp1up --c-toolchain   # ~/.sp1/riscv/bin/riscv64-unknown-elf-{gcc,g++,ar}
```

## Build

```bash
bash scripts/sp1_lean_runtime_fetch.sh
bash scripts/sp1_lean_runtime_build.sh
# → .cache/lean-sp1-runtime/prefix/lib/libLean.a
```

## Overlays in this directory

| File | Role |
| --- | --- |
| `shims.c` | `_sbrk`, atomics, unwind / POSIX stubs for the guest |
| `lean_guest_bridge.c` | ByteArray bridge for `lean_tee_guest_run` |
| `runtime_extern_stubs.c` | Missing runtime helpers (`lean_list_to_array`, …) |
| `once_probe.c` | Optional FENCE/once-cell bisect helper |
| `include/lean/config.h` | Lean 4.32.1 / SP1 platform config |

Fetched + patched sources live under `.cache/lean-sp1-runtime/` (gitignored).
