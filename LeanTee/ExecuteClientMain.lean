/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Grpc
import LeanTee.Guest
import LeanTee.Hash
import LeanTee.Proto

/-!
CLI client for live `lean_tee.v1.Tee/Execute` over lean-grpc h2c.

Usage:
  teeClient <host:port> <action> <rules-file> [guest_id]

Env: `LEAN_TEE_GUEST_ID` used when guest_id arg omitted (default compliance_operator / empty).
-/

open LeanTee
open LeanTee.Proto
open LeanTee.Grpc

def parseHostPort (s : String) : Option (String × UInt16) :=
  match s.splitOn ":" with
  | [h, p] =>
    match p.toNat? with
    | some n =>
      if n = 0 ∨ n > 65535 then none
      else some (h, UInt16.ofNat n)
    | none => none
  | _ => none

def jsonEscape (s : String) : String :=
  (s.replace "\\" "\\\\").replace "\"" "\\\""

def runExecute (host : String) (port : UInt16) (action rulesPath guestId : String) : IO UInt32 := do
  let rules ← IO.FS.readFile rulesPath
  let inputs := s!"action={action}\n".toUTF8
  let ch ← Grpc.Channel.connectH2c host port
  let tee : TeeStub := { channel := ch }
  let gid := if guestId.isEmpty then ByteArray.empty else guestId.toUTF8
  match ← tee.Execute {
      guestId := gid
      configHash := rules.toUTF8
      inputs
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
    if !receipt.hashMatches then
      IO.eprintln "resultHash mismatch"
      return 1
    let m := receipt.measurement
    let io := receipt.publicIO
    let parts : Array String := #[
      "\"job_id\":\"" ++ jsonEscape er.jobId ++ "\"",
      "\"guest_id\":\"" ++ jsonEscape guestId ++ "\"",
      "\"code_hash_hex\":\"" ++ Guest.hexEncode m.codeHash ++ "\"",
      "\"config_hash_hex\":\"" ++ Guest.hexEncode m.configHash ++ "\"",
      "\"inputs_hex\":\"" ++ Guest.hexEncode io.inputs ++ "\"",
      "\"outputs_hex\":\"" ++ Guest.hexEncode io.outputs ++ "\"",
      "\"nonce_hex\":\"" ++ Guest.hexEncode receipt.nonce ++ "\"",
      "\"evidence_root_hex\":\"" ++ Guest.hexEncode receipt.resultHash ++ "\"",
      "\"proof_ref_hex\":\"" ++ Guest.hexEncode receipt.proofRef ++ "\""
    ]
    IO.println ("{" ++ String.intercalate ", " parts.toList ++ "}")
    return 0

def main (args : List String) : IO UInt32 := do
  let envGuest := (← IO.getEnv "LEAN_TEE_GUEST_ID").getD ""
  match args with
  | [addr, action, rulesPath] =>
    match parseHostPort addr with
    | none =>
      IO.eprintln "usage: teeClient <host:port> <action> <rules-file> [guest_id]"
      return 1
    | some (host, port) => runExecute host port action rulesPath envGuest
  | [addr, action, rulesPath, guestId] =>
    match parseHostPort addr with
    | none =>
      IO.eprintln "usage: teeClient <host:port> <action> <rules-file> [guest_id]"
      return 1
    | some (host, port) => runExecute host port action rulesPath guestId
  | _ =>
    IO.eprintln "usage: teeClient <host:port> <action> <rules-file> [guest_id]"
    return 1
