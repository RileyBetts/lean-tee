# Lean SP1 runtime (Lean 4.32.1 → RISC-V)

Compiles a Lean **4.32.1** C++ runtime for SP1’s `riscv64im-succinct-zkvm-elf`.

Do **not** drop in [anoma/lean-risc0-runtime](https://github.com/anoma/lean-risc0-runtime) unchanged:
that tree targets Lean **4.22** (e.g. ST refs still take an IO “world” argument). Headers from
4.32.1 reject that ABI.

## Status

| Step | State |
| --- | --- |
| Fetch Lean `v4.32.1` `src/runtime` | `scripts/sp1_lean_runtime_fetch.sh` |
| Compile cores with SP1 g++ | `scripts/sp1_lean_runtime_build.sh` (fails until stubs) |
| `LEAN_SP1` stubs (threads, mmap, debug, no libuv) | **TODO** — mirror Anoma `LEAN_RISC0` on 4.32.1 sources |
| Init IR for SP1 | **TODO** (Anoma `lean-risc0-init` analogue) |
| Link GuestSp1 + portable sha256 | **TODO** |

## Prerequisites

```bash
sp1up --c-toolchain   # ~/.sp1/riscv/bin/riscv64-unknown-elf-{gcc,g++,ar}
```

## Build attempt

```bash
bash scripts/sp1_lean_runtime_fetch.sh
bash scripts/sp1_lean_runtime_build.sh
```

## Overlays in this directory

| File | Role |
| --- | --- |
| `shims.c` | `_sbrk`, atomics, unwind / POSIX stubs for the guest |
| `lean_guest_bridge.c` | ByteArray bridge for `lean_tee_guest_run` |
| `include/lean/config.h` | Lean 4.32.1 / SP1 platform config |

Fetched sources live under `.cache/lean-sp1-runtime/` (gitignored).
