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
  Hash.sha256 "lean-tee/compliance_operator/v1".toUTF8

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

def inputsAsString (inputs : ByteArray) : String :=
  match String.fromUTF8? inputs with
  | some s => s
  | none => ""

def trimStr (s : String) : String :=
  String.ofList (s.toList.dropWhile Char.isWhitespace |>.reverse.dropWhile Char.isWhitespace |>.reverse)

/-- Built-in defaults (Rust may narrow via `allow=` in rules). -/
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

def runCompliance (cfg : ComplianceConfig) (inputs : ByteArray) : ByteArray :=
  let text := inputsAsString inputs
  let allowed := actionAllowed text
  let decision := if allowed then "allow" else "deny"
  let reason := Hash.sha256 (Hash.concatLenPrefixed #[cfg.rulesHash, inputs])
  let reasonHex := hexEncode reason
  let _ := cfg.rulesRaw -- reserved for future Lean-side allow= parse
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
