/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Grpc
import LeanTee.Guest
import LeanTee.Proto
import LeanTee.Hash

/-!
Confidentiality=local demo client: public action + secret rules via secret_inputs.

Usage:
  confidentialClient <host:port> <action> <secret-rules-file>
-/

open LeanTee
open LeanTee.Proto
open LeanTee.Grpc

def parseHostPort (s : String) : Option (String × UInt16) :=
  match s.splitOn ":" with
  | [h, p] =>
    match p.toNat? with
    | some n =>
      if n = 0 ∨ n > 65535 then none else some (h, UInt16.ofNat n)
    | none => none
  | _ => none

def main (args : List String) : IO UInt32 := do
  match args with
  | [addr, action, secretPath] =>
    match parseHostPort addr with
    | none =>
      IO.eprintln "usage: confidentialClient <host:port> <action> <secret-rules-file>"
      return 1
    | some (host, port) =>
      let secretText ← IO.FS.readFile secretPath
      let secret := secretText.toUTF8
      let ch ← Grpc.Channel.connectH2c host port
      let tee : TeeStub := { channel := ch }
      let verify : VerifyStub := { channel := ch }
      match ← tee.Execute {
          guestId := "compliance_operator".toUTF8
          inputs := s!"action={action}\n".toUTF8
          secretInputs := secret
          nonce := ByteArray.empty
          submitToSink := false
        } with
      | .error e =>
        IO.eprintln s!"Execute failed: {e}"
        return 1
      | .ok er =>
        if er.status != "done" then
          IO.eprintln s!"status={er.status}"
          return 1
        let receipt ← match er.receipt with
          | some r => pure r
          | none =>
            IO.eprintln "missing receipt"
            return 1
        let pubIn := Guest.inputsAsString receipt.publicIO.inputs
        if (pubIn.splitOn secretText).length > 1 then
          IO.eprintln "FAIL: secret leaked into PublicIO.inputs"
          return 1
        let pubOut := Guest.inputsAsString receipt.publicIO.outputs
        if (pubOut.splitOn secretText).length > 1 then
          IO.eprintln "FAIL: secret leaked into PublicIO.outputs"
          return 1
        if receipt.receiptMeta.confidentiality != "local" then
          IO.eprintln "FAIL: expected confidentiality=local"
          return 1
        if receipt.receiptMeta.secretDigestHex.isEmpty then
          IO.eprintln "FAIL: missing secret_digest_hex"
          return 1
        if (pubIn.splitOn "secret_digest=").length <= 1 then
          IO.eprintln "FAIL: public inputs missing secret_digest="
          return 1
        match ← verify.AcceptReceipt {
            receipt
            proofOk := true
            requireConfidentiality := "local"
          } with
        | .error e =>
          IO.eprintln s!"Accept failed: {e}"
          return 1
        | .ok ar =>
          if !ar.accepted then
            IO.eprintln s!"Accept rejected: {ar.reason}"
            return 1
          IO.println s!"outputs={pubOut}"
          IO.println s!"confidentiality={receipt.receiptMeta.confidentiality}"
          IO.println s!"secret_digest_hex={receipt.receiptMeta.secretDigestHex}"
          IO.println s!"evidence_root_hex={Guest.hexEncode receipt.resultHash}"
          IO.println "confidentialClient OK"
          return 0
  | _ =>
    IO.eprintln "usage: confidentialClient <host:port> <action> <secret-rules-file>"
    return 1
