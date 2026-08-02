# Compliance operator guest

Logic is specified in Lean (`LeanTee.Guest` / `LeanTee.Guests`) and mirrored in Rust
`lean_tee_compliance`. The **SP1 RISC-V ELF** runs that Rust twin (not Lean source).

For **supplying a Lean-specified program** over gRPC to a measured RISC-V interpreter,
see [docs/GUEST_PROG.md](../../docs/GUEST_PROG.md) (`guest_prog_runtime`).

Inputs (UTF-8): `action=<name>\n…`  
Outputs: `decision=allow|deny` plus a reason digest.

Measurement (registry guests):

- `codeHash = SHA256("lean-tee/compliance_operator/v1")` (or other guest code_id)
- `configHash = SHA256(rules bytes)`
