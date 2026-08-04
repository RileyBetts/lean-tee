/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Hash
import LeanTee.Measurement

namespace LeanTee.Guest

/--
Deterministic compliance-operator guest model (v1 mock of the SP1 ELF path).

`allow=` lines in raw rules are interpreted by the Rust host (`lean_tee_receipt`);
the Lean oracle uses the default prefix list (sufficient for golden vectors).
-/
structure ComplianceConfig where
  rulesHash : ByteArray
  rulesRaw : ByteArray := ByteArray.empty
  deriving Inhabited

def demoCodeHash : ByteArray :=
  Hash.sha256 "lean-tee/compliance_operator/lean-sp1/v1".toUTF8

def demoGuestId : String := "compliance_operator"

def measurementOf (cfg : ComplianceConfig) : Measurement :=
  { codeHash := demoCodeHash
    configHash := Hash.sha256 cfg.rulesHash }

private def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + (n - 10))

def hexEncode (b : ByteArray) : String :=
  Id.run do
    let mut s := ""
    for i in [0:b.size] do
      let v := (b.get! i).toNat
      s := s.push (hexDigit (v >>> 4))
      s := s.push (hexDigit (v &&& 15))
    pure s

private def hexVal (c : Char) : Option Nat :=
  let n := c.toNat
  if n ≥ '0'.toNat && n ≤ '9'.toNat then some (n - '0'.toNat)
  else if n ≥ 'a'.toNat && n ≤ 'f'.toNat then some (n - 'a'.toNat + 10)
  else if n ≥ 'A'.toNat && n ≤ 'F'.toNat then some (n - 'A'.toNat + 10)
  else none

def hexDecode (s : String) : Option ByteArray :=
  let chars := s.toList.filter (fun c => !c.isWhitespace)
  if chars.length % 2 != 0 then none
  else
    Id.run do
      let mut out := ByteArray.empty
      let mut i := 0
      while i + 1 < chars.length do
        match hexVal chars[i]!, hexVal chars[i+1]! with
        | some hi, some lo =>
          out := out.push (UInt8.ofNat (hi * 16 + lo))
          i := i + 2
        | _, _ => return none
      return some out

def inputsAsString (inputs : ByteArray) : String :=
  match String.fromUTF8? inputs with
  | some s => s
  | none => ""

def trimStr (s : String) : String :=
  String.ofList (s.toList.dropWhile Char.isWhitespace |>.reverse.dropWhile Char.isWhitespace |>.reverse)

/-- Built-in defaults for compliance_operator when `allow=` absent. -/
def defaultAllowPrefixes : List String :=
  [ "action=vote.yes"
  , "action=vote.no"
  , "action=supplier.register"
  , "action=purchaser.approve"
  , "action=purchaser.reject"
  , "action=trade.submit"
  ]

def actionAllowed (text : String) : Bool :=
  defaultAllowPrefixes.any (fun p => text.startsWith p)

/-- Optional `allow=` from rules (compliance narrowing). -/
def parseAllow? (rulesRaw : ByteArray) : Option (List String) :=
  match String.fromUTF8? rulesRaw with
  | none => none
  | some text =>
    Id.run do
      for line in text.splitOn "\n" do
        let t := trimStr line
        if t.startsWith "allow=" then
          let rest := (t.splitOn "allow=").getD 1 ""
          let parts := rest.splitOn "," |>.map trimStr |>.filter (· ≠ "")
          let prefs := parts.map fun p =>
            if p.startsWith "action=" then p else s!"action={p}"
          if prefs.isEmpty then return none
          else return some prefs
      pure none

/-- Compliance guest oracle. Multi-guest path: `LeanTee.Guests.runGuest`. -/
def runCompliance (cfg : ComplianceConfig) (inputs : ByteArray) : ByteArray :=
  let text := inputsAsString inputs
  let allowed :=
    match parseAllow? cfg.rulesRaw with
    | some prefs => prefs.any (fun p => text.startsWith p)
    | none => actionAllowed text
  let decision := if allowed then "allow" else "deny"
  let reason := Hash.sha256 (Hash.concatLenPrefixed #[cfg.rulesHash, inputs])
  let reasonHex := hexEncode reason
  s!"decision={decision}\nreason={reasonHex}\n".toUTF8

def mockProof (m : Measurement) (inputs outputs : ByteArray) : ByteArray :=
  Hash.sha256 (Hash.concatLenPrefixed #[
    "lean-tee/mock-proof/v1".toUTF8,
    m.codeHash,
    m.configHash,
    inputs,
    outputs
  ])

def verifyMockProof (m : Measurement) (inputs outputs proof : ByteArray) : Bool :=
  Hash.bytesEq proof (mockProof m inputs outputs)

def bindInteraction (action interactionId payload : String) : ByteArray :=
  let base := s!"action={action}\ninteraction={interactionId}\n"
  let full :=
    if payload.isEmpty then base
    else base ++ payload ++ (if payload.endsWith "\n" then "" else "\n")
  full.toUTF8

end LeanTee.Guest
