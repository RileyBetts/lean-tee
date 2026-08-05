/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Guests.Registry
import LeanTee.Guest
import LeanTee.Hash

open LeanTee

def expect (cond : Bool) (msg : String) : IO Unit := do
  if !cond then throw (IO.userError msg)

def main : IO Unit := do
  expect (Guests.compliance.codeHash == Guest.demoCodeHash) "compliance codeHash"
  let mut seen : List ByteArray := []
  for g in Guests.builtin do
    expect (!(seen.any (Hash.bytesEq · g.codeHash))) s!"duplicate hash {g.guestId}"
    seen := g.codeHash :: seen
  match Guests.resolve "" with
  | .ok g => expect (g.guestId == "compliance_operator") "empty ⇒ compliance"
  | .error e => throw (IO.userError e)
  match Guests.resolve "nope" with
  | .ok _ => throw (IO.userError "unknown must fail")
  | .error _ => pure ()

  let rules := "allow=vote.yes\n".toUTF8
  let rh := Hash.sha256 rules
  let allow := Guests.runGuest Guests.voting rh rules "action=vote.yes\n".toUTF8
  expect ((Guest.inputsAsString allow).startsWith "decision=allow") "voting allow"
  let deny := Guests.runGuest Guests.voting rh rules "action=trade.submit\n".toUTF8
  expect ((Guest.inputsAsString deny).startsWith "decision=deny") "voting deny trade"
  let tradeAllow := Guests.runGuest Guests.trade rh ByteArray.empty "action=trade.submit\n".toUTF8
  expect ((Guest.inputsAsString tradeAllow).startsWith "decision=allow") "trade allow"
  IO.println "guestRegistry OK"
