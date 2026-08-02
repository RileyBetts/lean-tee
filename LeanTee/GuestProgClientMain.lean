/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Grpc
import LeanTee.Guest
import LeanTee.GuestProg
import LeanTee.Proto
import LeanTee.Hash

/-!
Supply a Lean-specified GuestProg over gRPC and Execute it on guest_prog_runtime.

Usage:
  guestProgClient <host:port> <prog-file> <action>
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
  | [addr, progPath, action] =>
    match parseHostPort addr with
    | none =>
      IO.eprintln "usage: guestProgClient <host:port> <prog-file> <action>"
      return 1
    | some (host, port) =>
      let text ← IO.FS.readFile progPath
      let raw := text.toUTF8
      let _ ← IO.ofExcept (GuestProg.parse raw)
      let ch ← Grpc.Channel.connectH2c host port
      let tee : TeeStub := { channel := ch }
      match ← tee.LoadProgram { program := { program := raw, name := "" } } with
      | .error e =>
        IO.eprintln s!"LoadProgram failed: {e}"
        return 1
      | .ok lr =>
        IO.println s!"loaded program_id={lr.programId} runtime={lr.runtimeGuestId}"
        match ← tee.Execute {
            programId := lr.programId
            inputs := s!"action={action}\n".toUTF8
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
          if !Hash.bytesEq receipt.measurement.codeHash GuestProg.runtimeCodeHash then
            IO.eprintln "runtime codeHash mismatch"
            return 1
          if !receipt.hashMatches then
            IO.eprintln "resultHash mismatch"
            return 1
          IO.println s!"outputs={Guest.inputsAsString receipt.publicIO.outputs}"
          IO.println s!"evidence_root_hex={Guest.hexEncode receipt.resultHash}"
          return 0
  | _ =>
    IO.eprintln "usage: guestProgClient <host:port> <prog-file> <action>"
    return 1
