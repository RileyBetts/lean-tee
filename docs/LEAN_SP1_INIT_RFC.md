# Lean SP1 Init allow-list RFC (Phase 4b)

**Status:** Accepted for the current measured guest (`lean_tee_guest_lean`).  
**Lean:** 4.32.1 · **SP1:** rv64im (no A, no FENCE) · **Branch context:** Phase 0–4a complete.

This RFC governs how the SP1 guest may grow its Lean `Init` / runtime surface. It is **not** a plan to run the Lean elaborator or kernel inside SP1.

## Current allow-list

Emitted and linked by [`scripts/sp1_lean_guest_build.sh`](../scripts/sp1_lean_guest_build.sh) (toolchain oleans → `l_*` C prefixes):

| Module | Role |
| --- | --- |
| `Init/Prelude.lean` | Core prelude |
| `Init/Data/List/Basic.lean` | List helpers used by Guest / GuestProg |
| `Init/Data/List/BasicAux.lean` | List aux |
| `Init/GetElem.lean` | Indexing |
| `Init/Data/String/Legacy.lean` | `splitOn` / legacy string ops |
| `Init/Util.lean` | Small util |

Minimal package init: [`host/lean_sp1_init_min/`](../host/lean_sp1_init_min/) (`initialize_Init` + transitive `STUB_INIT` + scalar `l_Nat_reprFast`).

Runtime: patched Lean 4.32.1 cores → `.cache/lean-sp1-runtime/prefix/lib/libLean.a` via [`scripts/sp1_lean_runtime_patch.py`](../scripts/sp1_lean_runtime_patch.py) (`LEAN_SP1`, fence-free once-cells).

Guest Lean modules in the archive: `GuestSp1`, `GuestProg`, `Guest`, `Hash`, `Measurement` + portable SHA + bridge/shims.

### Artifact sizes (local, Phase 4a era)

| Artifact | Size |
| --- | --- |
| `libLeanTeeGuest.a` | ~3.1 MiB |
| `libLean.a` | ~926 KiB |

## Lean-side shims (preferred over new Init)

[`LeanTee/GuestProg.lean`](../LeanTee/GuestProg.lean) deliberately avoids heavy Init:

| Need | Avoided Init | Local shim |
| --- | --- | --- |
| Join strings | `String.intercalate` → `Init.Data.String.Defs` | `joinSep` |
| Parse decimal | `String.toNat?` / `String.Slice` | `parseNatDec?` |
| Format Nat | `Nat.repr` / broken stub | `natToDec` (+ real `l_Nat_reprFast`) |
| BEq/Repr on `Program` | Meta/Syntax specializations | `deriving Inhabited` only |

**4b decision:** For the current GuestSp1 / GuestProg / compliance surface, **shims suffice**. No new Init module is admitted in this RFC revision.

## Known traps

1. **FENCE** — SP1 does not implement RISC-V `FENCE`. C11 `_Atomic` seq_cst loads (e.g. inlined `lean_obj_once`) trap. Fix: demote once-cells under `LEAN_SP1`; never ship guest C that emits `fence` in hot paths.
2. **Full `runtime_initialize_Init_Prelude`** — too heavy / unsafe on SP1; keep minimal `initialize_Init`.
3. **Stubbed `initialize_*`** — transitive inits return ok without side effects; do not rely on their closed values unless you actually emit and run that module.
4. **`l_Nat_reprFast`** — must format scalars correctly (GuestProg `max_input_bytes=` hashing).
5. **No IO / libuv / threads** — patched out; guest must stay pure ByteArray I/O at the bridge.
6. **Import explosion** — one Lake import of Slice/Defs/Omega/Iterators can pull megabytes of C and new atomics.

## Admission rule (new Init module)

Admit a module into `MODS` in `sp1_lean_guest_build.sh` only if **all** hold:

1. **Demand:** GuestSp1 / GuestProg / Hash / Measurement (or a documented new guest export) needs a symbol that cannot be replaced by a ≤30-line Lean shim without semantic drift vs host.
2. **Emit:** `lean -c` with toolchain oleans succeeds; object links with existing Init + `libLean.a` under `-march=rv64im`.
3. **ISA:** `riscv64-unknown-elf-objdump -d` on new `.o` files shows **zero** `fence` / `lr.` / `sc.` / `amo*` in reachable guest paths (or those ops are proven never executed).
4. **Smoke:** `sp1_smoke --execute-only` stays green.
5. **Budget:** cycle counts and archive size stay within the budgets below (or the PR explicitly bumps the budget with rationale).

Prefer **shim first**. Prefer **dropping `deriving Repr/BEq`** over pulling Meta.

## Cycle / size budgets (from Phase 4a baselines)

Baselines (local execute-only):

| Case | Baseline cycles |
| --- | --- |
| compliance allow/deny | ~73k–79k |
| GuestProg v1 | ~230k |
| GuestProg v2 allow | ~387k |

| Gate | Rule |
| --- | --- |
| Soft | Any listed case **> 2×** its baseline → justify in PR |
| Hard | Any listed case **> 3×** its baseline, or `libLeanTeeGuest.a` **> 6 MiB** → reject unless RFC amended |
| Soft size | `libLeanTeeGuest.a` **> 4.5 MiB** → justify in PR |

Record new numbers in [`docs/LEAN_SP1_GUEST.md`](LEAN_SP1_GUEST.md) when budgets are bumped.

## Explicitly rejected (unless a future RFC supersedes)

- Full Lean elaborator / kernel / `Lean.*` compiler stack
- `Init.Data.String.Slice`, `Defs`, Pattern/Iterator stacks (pull Omega / large deps)
- IO, process, libuv, networking, filesystem
- Switching prover backend to RISC0
- Marketing claim “formally verified Lean kernel on SP1” (pipeline trust only)

## Next-candidate modules (not admitted)

Only if demand appears and admission passes:

- Narrow pure List/Option helpers already half-covered by Basic (measure before adding).
- Never start with Slice / String.Defs / Meta.

## Process

1. Open PR titled `sp1-init: …` referencing this RFC.
2. Show: demand, shim attempt, `objdump` fence check, `sp1_smoke --execute-only` log with cycles, `ls -lh` of `libLeanTeeGuest.a`.
3. Update this RFC’s allow-list table if merged.
