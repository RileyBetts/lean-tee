/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Services
import LeanTee.Grpc

/-- Standalone Prove mock (for split-process demos). -/
def main : IO Unit := do
  let port : UInt16 :=
    match ← IO.getEnv "LEAN_TEE_PROVE_PORT" with
    | some s => match s.toNat? with | some n => n.toUInt16 | none => 50072
    | none => 50072
  let mut s := Grpc.Server.empty
  s := LeanTee.Grpc.registerProve s fun req => pure (LeanTee.Services.handleProve req)
  IO.println s!"lean-tee prove-mock on 127.0.0.1:{port.toNat}"
  Grpc.Server.serveH2c s { host := "127.0.0.1", port }
