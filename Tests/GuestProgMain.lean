/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.GuestProg
import LeanTee.Guest
import LeanTee.Hash

def expect (c : Bool) (m : String) : IO Unit := do
  if !c then throw (IO.userError m)

def main : IO Unit := do
  let p : LeanTee.GuestProg.Program := {
    name := "demo-votes"
    allow := ["vote.yes", "vote.no"]
  }
  let raw := p.serialize
  let p2 ← IO.ofExcept (LeanTee.GuestProg.parse raw)
  expect (p2.allow == p.allow) "parse allow"
  expect (LeanTee.Hash.bytesEq p.hash p2.hash) "hash stable"
  let allow := LeanTee.GuestProg.run p "action=vote.yes\n".toUTF8
  expect ((LeanTee.Guest.inputsAsString allow).startsWith "decision=allow") "allow"
  let deny := LeanTee.GuestProg.run p "action=trade.submit\n".toUTF8
  expect ((LeanTee.Guest.inputsAsString deny).startsWith "decision=deny") "deny"
  expect (LeanTee.GuestProg.runtimeGuestId == "guest_prog_runtime") "runtime id"
  IO.println "guestProgTests OK"
