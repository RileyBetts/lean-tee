/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.GuestProg
import LeanTee.Guest
import LeanTee.Hash
import LeanTee.Control

def expect (c : Bool) (m : String) : IO Unit := do
  if !c then throw (IO.userError m)

def main : IO Unit := do
  let p : LeanTee.GuestProg.Program := {
    name := "demo-votes"
    allow := ["vote.yes", "vote.no"]
  }
  let raw := p.serialize
  expect ((LeanTee.Guest.inputsAsString raw).startsWith "lean-tee-guest-prog/v1") "v1 wire"
  let p2 ← IO.ofExcept (LeanTee.GuestProg.parse raw)
  expect (p2.allow == p.allow) "parse allow"
  expect (LeanTee.Hash.bytesEq p.hash p2.hash) "hash stable"
  let allow := LeanTee.GuestProg.run p "action=vote.yes\n".toUTF8
  expect ((LeanTee.Guest.inputsAsString allow).startsWith "decision=allow") "allow"
  let deny := LeanTee.GuestProg.run p "action=trade.submit\n".toUTF8
  expect ((LeanTee.Guest.inputsAsString deny).startsWith "decision=deny") "deny"

  let v2 : LeanTee.GuestProg.Program := {
    name := "demo-v2"
    allow := ["vote.yes"]
    deny := ["vote.admin"]
    requireInteraction := true
    maxInputBytes := some 128
  }
  let raw2 := v2.serialize
  expect ((LeanTee.Guest.inputsAsString raw2).startsWith "lean-tee-guest-prog/v2") "v2 wire"
  let q ← IO.ofExcept (LeanTee.GuestProg.parse raw2)
  expect (q.requireInteraction) "require_interaction"
  expect (q.deny == ["vote.admin"]) "deny list"
  let missIx := LeanTee.GuestProg.run q "action=vote.yes\n".toUTF8
  expect ((LeanTee.Guest.inputsAsString missIx).startsWith "decision=deny") "deny without interaction"
  let ok := LeanTee.GuestProg.run q "action=vote.yes\ninteraction=cli\n".toUTF8
  expect ((LeanTee.Guest.inputsAsString ok).startsWith "decision=allow") "allow with interaction"
  let denied := LeanTee.GuestProg.run q "action=vote.admin\ninteraction=cli\n".toUTF8
  expect ((LeanTee.Guest.inputsAsString denied).startsWith "decision=deny") "deny wins"

  -- oversize program rejected
  match LeanTee.GuestProg.parse "lean-tee-guest-prog/v1\nallow=a\n".toUTF8 8 with
  | .error _ => pure ()
  | .ok _ => throw (IO.userError "expected size reject")

  -- LoadProgram ACL
  let acl : LeanTee.Control.AclFile := {
    loadProgramTenants := #["demo"]
  }
  expect (LeanTee.Control.aclAllowsLoadProgram acl "demo") "load ok"
  expect (!LeanTee.Control.aclAllowsLoadProgram acl "other") "load deny"
  expect (LeanTee.Control.aclAllowsLoadProgram {} "anyone") "empty unrestricted"

  expect (LeanTee.GuestProg.runtimeGuestId == "guest_prog_runtime") "runtime id"
  IO.println "guestProgTests OK"
