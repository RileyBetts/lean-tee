/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Hash
import LeanTee.Measurement

namespace LeanTee.Guest

/--
Deterministic compliance-operator guest model (v1 mock of the SP1 ELF path).

Single measured path: interface framing + compliance main in one logical guest.
Outputs: `allow|deny` + reason digest, derived from inputs and config.
-/
structure ComplianceConfig where
  rulesHash : ByteArray
  deriving Inhabited

def demoCodeHash : ByteArray :=
  Hash.sha256 "lean-tee/compliance_operator/v1".toUTF8

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

/-- Decode inputs as UTF-8 when valid; otherwise treat as empty action (deny). -/
def inputsAsString (inputs : ByteArray) : String :=
  match String.fromUTF8? inputs with
  | some s => s
  | none => ""

/-- Allowed action prefixes for the demo compliance operator (integrity-first). -/
def actionAllowed (text : String) : Bool :=
  text.startsWith "action=vote.yes"
    || text.startsWith "action=vote.no"
    || text.startsWith "action=supplier.register"
    || text.startsWith "action=purchaser.approve"
    || text.startsWith "action=purchaser.reject"
    || text.startsWith "action=trade.submit"

/--
Main execution path (interface + compliance). Entire output is what gets hashed/proved.
Input format (UTF-8): `action=<name>\n` plus optional trailing payload bytes.
-/
def runCompliance (cfg : ComplianceConfig) (inputs : ByteArray) : ByteArray :=
  let text := inputsAsString inputs
  let allowed := actionAllowed text
  let decision := if allowed then "allow" else "deny"
  let reason := Hash.sha256 (Hash.concatLenPrefixed #[cfg.rulesHash, inputs])
  let reasonHex := hexEncode reason
  s!"decision={decision}\nreason={reasonHex}\n".toUTF8

/-- Mock proof: binds measurement + I/O (stand-in until SP1 Hypercube wiring). -/
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

end LeanTee.Guest
