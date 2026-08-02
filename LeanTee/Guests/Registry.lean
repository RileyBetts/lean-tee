/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Hash
import LeanTee.Guest

namespace LeanTee.Guests

structure GuestDesc where
  guestId : String
  codeId : String
  enabled : Bool := true
  defaultProfile : String := "lean-tee-v1"
  actions : List String
  deriving Inhabited

def GuestDesc.codeHash (g : GuestDesc) : ByteArray :=
  Hash.sha256 g.codeId.toUTF8

def GuestDesc.allowPrefixes (g : GuestDesc) : List String :=
  g.actions.map (fun a => s!"action={a}")

def compliance : GuestDesc := {
  guestId := "compliance_operator"
  codeId := "lean-tee/compliance_operator/v1"
  actions := [
    "vote.yes", "vote.no", "supplier.register",
    "purchaser.approve", "purchaser.reject", "trade.submit"
  ]
}

def voting : GuestDesc := {
  guestId := "voting_operator"
  codeId := "lean-tee/voting_operator/v1"
  actions := ["vote.yes", "vote.no"]
}

def onboarding : GuestDesc := {
  guestId := "onboarding_operator"
  codeId := "lean-tee/onboarding_operator/v1"
  actions := ["supplier.register", "purchaser.approve", "purchaser.reject"]
}

def trade : GuestDesc := {
  guestId := "trade_operator"
  codeId := "lean-tee/trade_operator/v1"
  actions := ["trade.submit"]
}

/-- Measured RISC-V interpreter for Lean-specified GuestProg payloads. -/
def guestProgRuntime : GuestDesc := {
  guestId := "guest_prog_runtime"
  codeId := "lean-tee/guest_prog_runtime/v1"
  actions := []  -- allow-list comes from the loaded program
}

def builtin : List GuestDesc := [compliance, voting, onboarding, trade, guestProgRuntime]

def aliases (id : String) : String :=
  if id.isEmpty || id == "compliance_operator/v1" then "compliance_operator"
  else id

def findBuiltin (guestId : String) : Option GuestDesc :=
  let id := aliases (Guest.trimStr guestId)
  builtin.find? (fun g => g.guestId == id && g.enabled)

/-- Resolve guest_id → descriptor (builtin registry). Unknown ⇒ none. -/
def resolve (guestId : String) : Except String GuestDesc :=
  match findBuiltin guestId with
  | some g => .ok g
  | none => .error s!"unknown guest_id={Guest.trimStr guestId}"

def resolveCodeHash (guestId : ByteArray) : Except String ByteArray := do
  let id :=
    match String.fromUTF8? guestId with
    | some s => s
    | none => ""
  let g ← resolve id
  pure g.codeHash

/-- Parse optional `allow=` line; intersect with guest built-in actions. -/
def effectivePrefixes (g : GuestDesc) (rulesRaw : ByteArray) : List String :=
  let builtin := g.allowPrefixes
  match Guest.parseAllow? rulesRaw with
  | none => builtin
  | some asked =>
    let filtered := asked.filter fun p => builtin.any (· == p)
    if filtered.isEmpty then builtin else filtered

def runGuest (g : GuestDesc) (rulesHash rulesRaw inputs : ByteArray) : ByteArray :=
  let text := Guest.inputsAsString inputs
  let prefs := effectivePrefixes g rulesRaw
  let allowed := prefs.any (fun p => text.startsWith p)
  let decision := if allowed then "allow" else "deny"
  let reason := Hash.sha256 (Hash.concatLenPrefixed #[rulesHash, inputs])
  s!"decision={decision}\nreason={Guest.hexEncode reason}\n".toUTF8

end LeanTee.Guests
