# Legacy Rust SP1 guest twin

This crate (`lean_tee_guest`) is the **pre–Phase-3** Rust semantic twin of the
compliance / GuestProg guest.

**Measured production ELF** is now Lean-compiled [`../guest_lean`](../guest_lean)
(`lean_tee_guest_lean`), built via `scripts/sp1_lean_guest_build.sh` and linked
from `prove_server` / `sp1_smoke`.

Keep this crate for differential checks against `lean_tee_compliance::run_measured`
if needed; it is not built into the Prove server by default.
