/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Services
import LeanTee.Grpc
import LeanTee.Guest
import LeanTee.Hash
import LeanTee.Receipt

/-- Spawn integrated teeServer and exercise Execute → AcceptReceipt → Submit over lean-grpc. -/
def main : IO Unit := do
  let port : UInt16 := 50073
  let binDir := ← IO.appDir
  let serverPath := binDir / "teeServer"
  let child ← IO.Process.spawn {
    cmd := serverPath.toString
    env := #[
      ("LEAN_TEE_PORT", some (toString port.toNat)),
      ("LEAN_TEE_DEFAULT_PROFILE", some "lean-tee-v1")
    ]
  }
  try
    IO.sleep 600
    let ch ← Grpc.Channel.connectH2c "127.0.0.1" port
    let tee : LeanTee.Grpc.TeeStub := { channel := ch }
    let verify : LeanTee.Grpc.VerifyStub := { channel := ch }
    let sink : LeanTee.Grpc.AnchorSinkStub := { channel := ch }

    let rules := "rules=vote.yes,vote.no".toUTF8
    let inputs := "action=vote.yes\n".toUTF8
    match ← tee.Measure { configHash := rules } with
    | .error e => throw (IO.userError s!"Measure: {e}")
    | .ok mr =>
      let m := mr.measurement
      if m.codeHash.size != 32 then throw (IO.userError "bad codeHash")

      match ← tee.Execute {
          configHash := rules
          inputs
          nonce := "loopback-nonce".toUTF8
          submitToSink := false
        } with
      | .error e => throw (IO.userError s!"Execute: {e}")
      | .ok er =>
        if er.status != "done" then throw (IO.userError s!"status {er.status}")
        let receipt ← match er.receipt with
          | some r => pure r
          | none => throw (IO.userError "missing receipt")
        if !receipt.hashMatches then throw (IO.userError "receipt hash mismatch")
        if !LeanTee.Guest.verifyMockProof receipt.measurement receipt.publicIO.inputs
            receipt.publicIO.outputs receipt.proofRef then
          throw (IO.userError "mock proof failed")

        match ← verify.AcceptReceipt {
            receipt
            policyCodeHash := m.codeHash
            policyConfigHash := m.configHash
            proofOk := true
          } with
        | .error e => throw (IO.userError s!"Accept: {e}")
        | .ok ar =>
          if !ar.accepted then throw (IO.userError s!"rejected: {ar.reason}")

        -- Adversarial forged receipt
        let forged := { receipt with
          publicIO := { receipt.publicIO with outputs := "decision=allow\nforged".toUTF8 }
          resultHash := receipt.resultHash
        }
        match ← verify.AcceptReceipt {
            receipt := forged
            policyCodeHash := m.codeHash
            policyConfigHash := m.configHash
            proofOk := true
          } with
        | .error e => throw (IO.userError s!"Accept forged: {e}")
        | .ok ar =>
          if ar.accepted then throw (IO.userError "forged receipt must be rejected")
          if ar.reason != "resultHash mismatch" then
            throw (IO.userError s!"unexpected reason: {ar.reason}")

        match ← sink.Submit { receipt } with
        | .error e => throw (IO.userError s!"Submit: {e}")
        | .ok ack =>
          if !ack.ok then throw (IO.userError "submit not ok")

        match ← tee.GetReceipt { jobId := er.jobId } with
        | .error e => throw (IO.userError s!"GetReceipt: {e}")
        | .ok gr =>
          if gr.status != "done" then throw (IO.userError "job not done")

    IO.println "teeLoopback OK"
  finally
    child.kill
