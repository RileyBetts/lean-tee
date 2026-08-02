/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Std.Data.HashMap
import LeanTee.Guest
import LeanTee.Receipt
import LeanTee.Proto
import LeanTee.Grpc
import LeanTee.Hash

namespace LeanTee.Services
open LeanTee
open LeanTee.Proto
open LeanTee.Grpc

/-- In-memory job store for async Execute (v1). -/
structure JobStore where
  jobs : IO.Ref (Std.HashMap String TeeReceipt)

def JobStore.new : IO JobStore := do
  let jobs ← IO.mkRef (∅ : Std.HashMap String TeeReceipt)
  return { jobs }

def JobStore.put (self : JobStore) (id : String) (r : TeeReceipt) : IO Unit := do
  self.jobs.modify fun m => m.insert id r

def JobStore.get? (self : JobStore) (id : String) : IO (Option TeeReceipt) := do
  let m ← self.jobs.get
  return m[id]?

/-- Local (in-process) mock prove — same logic as Prove gRPC service. -/
def proveLocal (req : ProveRequest) : ProveResponse :=
  let outputs := Guest.runCompliance { rulesHash := req.measurement.configHash } req.inputs
  let proof := Guest.mockProof req.measurement req.inputs outputs
  { outputs, proofRef := proof }

def verifyProofOk (r : TeeReceipt) : Bool :=
  Guest.verifyMockProof r.measurement r.publicIO.inputs r.publicIO.outputs r.proofRef

def buildReceipt (m : Measurement) (inputs outputs nonce proofRef : ByteArray) : TeeReceipt :=
  let io : PublicIO := { inputs, outputs }
  TeeReceipt.withComputedHash {
    measurement := m
    publicIO := io
    resultHash := ByteArray.empty
    nonce
    proofRef
    receiptMeta := { version := "v1", domain := "lean-tee/v1", sinkId := "lean-tee/mock" }
  }

def handleMeasure (req : MeasureRequest) : MeasureResponse × Grpc.Status :=
  -- `configHash` request field carries raw rules bytes; measurement stores SHA-256(rules).
  let m : Measurement := { codeHash := Guest.demoCodeHash, configHash := Hash.sha256 req.configHash }
  ({ measurement := m }, Grpc.Status.ok)

/-- Execute: prove locally (or via Prove stub if channel provided), build receipt, store job. -/
def handleExecute (store : JobStore) (prove? : Option ProveStub) (sink? : Option AnchorSinkStub)
    (req : ExecuteRequest) : IO (ExecuteResponse × Grpc.Status) := do
  let m : Measurement := {
    codeHash := Guest.demoCodeHash
    configHash := Hash.sha256 req.configHash
  }
  let proveResp ← match prove? with
    | none => pure (proveLocal { measurement := m, inputs := req.inputs })
    | some stub =>
      match ← stub.Prove { measurement := m, inputs := req.inputs } with
      | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.internal e)
      | .ok r => pure r
  let nonce :=
    if req.nonce.isEmpty then Hash.sha256 (Hash.concatLenPrefixed #[req.inputs, m.configHash])
    else req.nonce
  let receipt := buildReceipt m req.inputs proveResp.outputs nonce proveResp.proofRef
  let jobId := Guest.hexEncode (Hash.sha256 (Hash.concatLenPrefixed #[nonce, receipt.resultHash]))
  store.put jobId receipt
  if req.submitToSink then
    match sink? with
    | none => pure ()
    | some sink =>
      let _ ← sink.Submit { receipt }
      pure ()
  return ({ jobId, receipt := some receipt, status := "done" }, Grpc.Status.ok)

def handleGetReceipt (store : JobStore) (req : GetReceiptRequest) :
    IO (ExecuteResponse × Grpc.Status) := do
  match ← store.get? req.jobId with
  | none => return ({ jobId := req.jobId, status := "pending" }, Grpc.Status.ok)
  | some r => return ({ jobId := req.jobId, receipt := some r, status := "done" }, Grpc.Status.ok)

def handleAccept (req : AcceptReceiptRequest) : AcceptReceiptResponse × Grpc.Status :=
  let policy : MeasurementPolicy := {
    allowed := #[{ codeHash := req.policyCodeHash, configHash := req.policyConfigHash }]
  }
  -- Mock proofs verify in Lean; SP1 proofs are verified by the Prove host, then
  -- clients set `proofOk := true` (committee should re-verify SP1 on chain).
  let proofOk :=
    if verifyProofOk req.receipt then true
    else req.proofOk
  match TeeReceipt.acceptReceipt policy req.receipt proofOk with
  | .accept => ({ accepted := true, reason := "" }, Grpc.Status.ok)
  | .reject why => ({ accepted := false, reason := why }, Grpc.Status.ok)

def handleSubmit (submitted : IO.Ref (Array TeeReceipt)) (req : SubmitRequest) :
    IO (SubmitAck × Grpc.Status) := do
  submitted.modify fun a => a.push req.receipt
  let n ← submitted.get
  let ref := s!"sink-{n.size}"
  return ({ ok := true, ref, message := "stored" }, Grpc.Status.ok)

def handleProve (req : ProveRequest) : ProveResponse × Grpc.Status :=
  (proveLocal req, Grpc.Status.ok)

/-- Build a server with Tee + Verify + optional in-process Prove + AnchorSink. -/
def mkIntegratedServer (store : JobStore) (submitted : IO.Ref (Array TeeReceipt))
    (includeProve : Bool := true) : Grpc.Server :=
  Id.run do
    let mut s := Grpc.Server.empty
    s := registerTeeExecute s (handleExecute store none none)
    s := registerTeeGetReceipt s (handleGetReceipt store)
    s := registerTeeMeasure s fun req => pure (handleMeasure req)
    s := registerVerifyAccept s fun req => pure (handleAccept req)
    s := registerAnchorSinkSubmit s (handleSubmit submitted)
    if includeProve then
      s := registerProve s fun req => pure (handleProve req)
    return s

end LeanTee.Services
