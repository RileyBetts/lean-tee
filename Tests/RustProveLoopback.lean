/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Services
import LeanTee.Grpc
import LeanTee.Guest
import LeanTee.Receipt

/--
Requires `prove_server` already listening on LEAN_TEE_PROVE_PORT (default 50072).
Spawns teeServer with LEAN_TEE_PROVE_ADDR and checks Execute → AcceptReceipt.
-/
def main : IO Unit := do
  let provePort : UInt16 :=
    match ← IO.getEnv "LEAN_TEE_PROVE_PORT" with
    | some s => match s.toNat? with | some n => n.toUInt16 | none => 50072
    | none => 50072
  let teePort : UInt16 := 50074
  let binDir := ← IO.appDir
  let child ← IO.Process.spawn {
    cmd := (binDir / "teeServer").toString
    env := #[
      ("LEAN_TEE_PORT", some (toString teePort.toNat)),
      ("LEAN_TEE_PROVE_ADDR", some s!"127.0.0.1:{provePort.toNat}")
    ]
  }
  try
    IO.sleep 700
    let ch ← Grpc.Channel.connectH2c "127.0.0.1" teePort
    let tee : LeanTee.Grpc.TeeStub := { channel := ch }
    let verify : LeanTee.Grpc.VerifyStub := { channel := ch }
    let rules := "rules=vote.yes,vote.no".toUTF8
    match ← tee.Measure { configHash := rules } with
    | .error e => throw (IO.userError e)
    | .ok mr =>
      match ← tee.Execute {
          configHash := rules
          inputs := "action=vote.yes\n".toUTF8
          nonce := "rust-prove-nonce".toUTF8
          submitToSink := false
        } with
      | .error e => throw (IO.userError s!"Execute via Rust Prove: {e}")
      | .ok er =>
        let receipt ← match er.receipt with
          | some r => pure r
          | none => throw (IO.userError "no receipt")
        if !receipt.hashMatches then throw (IO.userError "hash mismatch")
        match ← verify.AcceptReceipt {
            receipt
            policyCodeHash := mr.measurement.codeHash
            policyConfigHash := mr.measurement.configHash
            proofOk := true
          } with
        | .error e => throw (IO.userError e)
        | .ok ar =>
          if !ar.accepted then throw (IO.userError s!"reject: {ar.reason}")
    IO.println "rustProveLoopback OK"
  finally
    child.kill
