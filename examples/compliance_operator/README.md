# Compliance operator guest

Logic is specified in Lean (`LeanTee.Guest` / `LeanTee.Guests`) and mirrored in Rust
`lean_tee_compliance` for mock / host parity. The **measured SP1 ELF** is
Lean-compiled (`lean_tee_guest_lean`), not the legacy Rust twin.

For **supplying a Lean-specified program** over gRPC, see
[docs/GUEST_PROG.md](../../docs/GUEST_PROG.md) (`guest_prog_runtime`).

Inputs (UTF-8): `action=<name>\n…`  
Outputs: `decision=allow|deny` plus a reason digest.

Measurement (registry guests):

- `codeHash = SHA256("lean-tee/compliance_operator/lean-sp1/v1")` (or other guest code_id)
- `configHash = SHA256(rules bytes)`
