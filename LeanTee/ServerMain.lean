/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Services
import LeanTee.Grpc

def parseHostPort (addr : String) : IO (String × UInt16) := do
  match addr.splitOn ":" with
  | [h, p] =>
    match p.toNat? with
    | some n => pure (h, n.toUInt16)
    | none => throw (IO.userError s!"bad port in {addr}")
  | _ => throw (IO.userError s!"expected host:port, got {addr}")

/--
Integrated Tee + Verify + AnchorSink on h2c.
If `LEAN_TEE_PROVE_ADDR=host:port` is set, dials remote `Prove` (e.g. Rust host).
Otherwise registers in-process Lean mock Prove.
-/
def main : IO Unit := do
  let port : UInt16 :=
    match ← IO.getEnv "LEAN_TEE_PORT" with
    | some s => match s.toNat? with | some n => n.toUInt16 | none => 50071
    | none => 50071
  let store ← LeanTee.Services.JobStore.new
  let submitted ← IO.mkRef (#[] : Array LeanTee.TeeReceipt)

  match ← IO.getEnv "LEAN_TEE_PROVE_ADDR" with
  | some addr =>
    let (host, p) ← parseHostPort addr
    let ch ← Grpc.Channel.connectH2c host p
    let prove : LeanTee.Grpc.ProveStub := { channel := ch }
    let mut s := Grpc.Server.empty
    s := LeanTee.Grpc.registerTeeExecute s
      (LeanTee.Services.handleExecute store (some prove) none)
    s := LeanTee.Grpc.registerTeeGetReceipt s (LeanTee.Services.handleGetReceipt store)
    s := LeanTee.Grpc.registerTeeMeasure s fun req => pure (LeanTee.Services.handleMeasure req)
    s := LeanTee.Grpc.registerVerifyAccept s fun req => pure (LeanTee.Services.handleAccept req)
    s := LeanTee.Grpc.registerAnchorSinkSubmit s (LeanTee.Services.handleSubmit submitted)
    IO.println s!"lean-tee server 127.0.0.1:{port.toNat} (Prove → {host}:{p.toNat})"
    Grpc.Server.serveH2c s { host := "127.0.0.1", port }
  | none =>
    let s := LeanTee.Services.mkIntegratedServer store submitted true
    IO.println s!"lean-tee server 127.0.0.1:{port.toNat} (in-process Prove)"
    Grpc.Server.serveH2c s { host := "127.0.0.1", port }
