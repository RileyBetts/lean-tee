/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Guest
import LeanTee.Hash

/-!
# SP1 Lean guest entry (phase 1+)

Pure, IO-free entry matching the SP1 guest public ABI:

* empty `program` → compliance oracle (`Guest.runCompliance`)
* non-empty `program` → reserved for GuestProg (phase 2); currently fixed deny

No Services / Grpc imports — keep the SP1 link set small.
-/

namespace LeanTee.GuestSp1

/-- Fixed deny when program bytes are present before GuestProg lands in-guest. -/
private def denyNotImplemented : ByteArray :=
  -- reason must be 64 hex chars for receipt shape parity with host deny paths that use digests;
  -- use a domain-separated hash so it is well-formed, not a magic string.
  let reason := Hash.sha256 "lean-tee/sp1-guest/program-path-pending".toUTF8
  s!"decision=deny\nreason={Guest.hexEncode reason}\n".toUTF8

/--
SP1 measured entry.

`configHash` is the rules hash for the compliance path (same as today's Rust
`run_measured` when `program` is empty).
-/
@[export lean_tee_guest_run]
def guestRun (configHash inputs program : ByteArray) : ByteArray :=
  if program.size == 0 then
    Guest.runCompliance { rulesHash := configHash, rulesRaw := ByteArray.empty } inputs
  else
    denyNotImplemented

end LeanTee.GuestSp1
