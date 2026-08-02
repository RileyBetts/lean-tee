# Compliance operator guest

v1 guest logic lives in Lean as `LeanTee.Guest.runCompliance` (single measured path: interface framing + policy decision).

Inputs (UTF-8): `action=<name>\n…`  
Outputs: `decision=allow|deny` plus a reason digest.

This is the stand-in for a RISC-V ELF proved by SP1. Measurement:

- `codeHash = SHA256("lean-tee/compliance_operator/v1")`
- `configHash = SHA256(rules bytes)`
