/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Guest
import LeanTee.GuestProg
import LeanTee.Guests.Registry
import LeanTee.Hash

/-!
# SP1 Lean guest entry

Pure, IO-free entry matching the SP1 guest public ABI:

* `codeHash` — logical guest measurement (`SHA256(code_id)`); selects builtin surface
* empty `program` → multi-guest compliance (`Guests.runGuest`) with optional `rules`
* non-empty `program` → GuestProg (`GuestProg.runBytes`); requires
  `codeHash = guest_prog_runtime` and `configHash = SHA256(program)`

No Services / Grpc imports — keep the SP1 link set small.
-/

namespace LeanTee.GuestSp1

/-- Match Rust twin: parse / hash mismatch → fixed guest_error deny. -/
private def denyGuestError : ByteArray :=
  "decision=deny\nreason=guest_error\n".toUTF8

/--
SP1 measured entry.

`rules` is the raw config bytes for the compliance path (may be empty). When
non-empty, `SHA256(rules)` must equal `configHash`. GuestProg path ignores `rules`.
-/
@[export lean_tee_guest_run]
def guestRun (codeHash configHash inputs program rules : ByteArray) : ByteArray :=
  if program.size != 0 then
    if !Hash.bytesEq codeHash Guests.guestProgRuntime.codeHash then
      denyGuestError
    else if !Hash.bytesEq (Hash.sha256 program) configHash then
      denyGuestError
    else
      match GuestProg.runBytes program inputs with
      | .ok out => out
      | .error _ => denyGuestError
  else
    match Guests.builtin.find? (fun g => Hash.bytesEq g.codeHash codeHash) with
    | none => denyGuestError
    | some g =>
      if g.guestId == Guests.guestProgRuntime.guestId then
        denyGuestError
      else if rules.size != 0 && !Hash.bytesEq (Hash.sha256 rules) configHash then
        denyGuestError
      else
        Guests.runGuest g configHash rules inputs

end LeanTee.GuestSp1
