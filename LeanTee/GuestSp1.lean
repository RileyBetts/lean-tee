/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Guest
import LeanTee.GuestProg
import LeanTee.Hash

/-!
# SP1 Lean guest entry (phase 1–2)

Pure, IO-free entry matching the SP1 guest public ABI:

* empty `program` → compliance oracle (`Guest.runCompliance`)
* non-empty `program` → Lean GuestProg (`GuestProg.runBytes`), requiring
  `configHash = SHA256(program)` (same as Rust `run_measured`)

No Services / Grpc imports — keep the SP1 link set small.
-/

namespace LeanTee.GuestSp1

/-- Match Rust twin: parse / hash mismatch → fixed guest_error deny. -/
private def denyGuestError : ByteArray :=
  "decision=deny\nreason=guest_error\n".toUTF8

/--
SP1 measured entry.

`configHash` is the rules hash for the compliance path, or `SHA256(program)`
when `program` is non-empty.
-/
@[export lean_tee_guest_run]
def guestRun (configHash inputs program : ByteArray) : ByteArray :=
  if program.size == 0 then
    Guest.runCompliance { rulesHash := configHash, rulesRaw := ByteArray.empty } inputs
  else if !Hash.bytesEq (Hash.sha256 program) configHash then
    denyGuestError
  else
    match GuestProg.runBytes program inputs with
    | .ok out => out
    | .error _ => denyGuestError

end LeanTee.GuestSp1
