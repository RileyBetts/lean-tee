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
import LeanTee.Measurement

namespace LeanTee.Services
open LeanTee
open LeanTee.Proto
open LeanTee.Grpc

/-- In-memory job store for async Execute (v1 sync completion). -/
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

/-- Guest registry: guest_id UTF-8 → code hash (v1: one compliance operator). -/
def resolveGuestCodeHash (guestId : ByteArray) : Except String ByteArray :=
  let id :=
    match String.fromUTF8? guestId with
    | some s => Guest.trimStr s
    | none => ""
  if id.isEmpty || id == Guest.demoGuestId || id == "compliance_operator/v1" then
    .ok Guest.demoCodeHash
  else
    .error s!"unknown guest_id={id}"

/-- Optional multi-entry policy from `LEAN_TEE_POLICY_FILE` (hex lines `codeHex configHex`). -/
structure ServerPolicy where
  entries : Array Measurement := #[]
  deriving Inhabited

def ServerPolicy.allows (p : ServerPolicy) (m : Measurement) : Bool :=
  if p.entries.isEmpty then true
  else p.entries.any (Measurement.beq · m)

def loadPolicyFile (path : String) : IO ServerPolicy := do
  let text ← IO.FS.readFile path
  let mut entries : Array Measurement := #[]
  for line in text.splitOn "\n" do
    let t := Guest.trimStr line
    if t.isEmpty || t.startsWith "#" then continue
    let parts := t.splitOn " " |>.filter (· ≠ "")
    match parts with
    | [c, cfg] =>
      match Hash.hexDecode? c, Hash.hexDecode? cfg with
      | some codeHash, some configHash =>
        entries := entries.push { codeHash, configHash }
      | _, _ => pure ()
    | _ => pure ()
  return { entries }

/-- Pluggable AnchorSink backends. -/
inductive SinkBackend where
  | memory (buf : IO.Ref (Array TeeReceipt))
  | print
  | webhook (url : String)

def SinkBackend.submit (b : SinkBackend) (r : TeeReceipt) : IO (String × String) := do
  match b with
  | .memory buf =>
    buf.modify fun a => a.push r
    let n ← buf.get
    pure (s!"sink-{n.size}", "stored")
  | .print =>
    IO.println s!"AnchorSink receipt resultHash={Guest.hexEncode r.resultHash}"
    pure ("sink-print", "printed")
  | .webhook url =>
    -- v1: record intent only (no HTTP client in Lean); message carries URL.
    pure ("sink-webhook", s!"queued url={url}")

/-- Local mock prove with raw rules for `allow=`. -/
def proveLocal (rulesRaw : ByteArray) (req : ProveRequest) : ProveResponse :=
  let outputs := Guest.runCompliance {
    rulesHash := req.measurement.configHash
    rulesRaw
  } req.inputs
  let proof := Guest.mockProof req.measurement req.inputs outputs
  { outputs, proofRef := proof }

def verifyMockProofOk (r : TeeReceipt) : Bool :=
  Guest.verifyMockProof r.measurement r.publicIO.inputs r.publicIO.outputs r.proofRef

def buildReceipt (m : Measurement) (inputs outputs nonce proofRef : ByteArray) : TeeReceipt :=
  let io : PublicIO := { inputs, outputs }
  TeeReceipt.withComputedHash {
    measurement := m
    publicIO := io
    resultHash := ByteArray.empty
    nonce
    proofRef
    receiptMeta := { version := "v1", domain := "lean-tee/v1", sinkId := "lean-tee" }
  }

def handleMeasure (req : MeasureRequest) : MeasureResponse × Grpc.Status :=
  match resolveGuestCodeHash ByteArray.empty with
  | .error e => ({ measurement := default }, Grpc.Status.invalidArgument e)
  | .ok codeHash =>
    let m : Measurement := { codeHash, configHash := Hash.sha256 req.configHash }
    ({ measurement := m }, Grpc.Status.ok)

def handleExecute (store : JobStore) (prove? : Option ProveStub) (sink? : Option SinkBackend)
    (req : ExecuteRequest) : IO (ExecuteResponse × Grpc.Status) := do
  let codeHash ← match resolveGuestCodeHash req.guestId with
    | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.invalidArgument e)
    | .ok h => pure h
  let m : Measurement := { codeHash, configHash := Hash.sha256 req.configHash }
  let proveResp ← match prove? with
    | none => pure (proveLocal req.configHash { measurement := m, inputs := req.inputs })
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
      let _ ← sink.submit receipt
      pure ()
  return ({ jobId, receipt := some receipt, status := "done" }, Grpc.Status.ok)

def handleGetReceipt (store : JobStore) (req : GetReceiptRequest) :
    IO (ExecuteResponse × Grpc.Status) := do
  match ← store.get? req.jobId with
  | none => return ({ jobId := req.jobId, status := "pending" }, Grpc.Status.ok)
  | some r => return ({ jobId := req.jobId, receipt := some r, status := "done" }, Grpc.Status.ok)

/--
AcceptReceipt: measurement policy + resultHash + proof.

For lean-tee-v1 mock proofs, Lean verifies the mock digest.
For non-mock proofs (lean-tee-v2), `proofOk` is accepted only when the mock
check fails *and* the caller is the host verify path (`LEAN_TEE_TRUST_PROOF_OK=1`
set by trusted host adapters — not for untrusted clients). Default: reject
non-mock unless mock verifies.
-/
def handleAccept (policy : ServerPolicy) (trustProofOk : Bool) (req : AcceptReceiptRequest) :
    AcceptReceiptResponse × Grpc.Status :=
  let reqPolicy : MeasurementPolicy := {
    allowed := #[{ codeHash := req.policyCodeHash, configHash := req.policyConfigHash }]
  }
  let measurementOk :=
    (req.policyCodeHash.isEmpty && req.policyConfigHash.isEmpty && policy.allows req.receipt.measurement)
    || reqPolicy.allows req.receipt.measurement
    || (policy.entries.isEmpty && !req.policyCodeHash.isEmpty && reqPolicy.allows req.receipt.measurement)
  let mockOk := verifyMockProofOk req.receipt
  let proofOk :=
    if mockOk then true
    else if trustProofOk then req.proofOk
    else false
  if !measurementOk then
    ({ accepted := false, reason := "measurement not in policy" }, Grpc.Status.ok)
  else if !req.receipt.hashMatches then
    ({ accepted := false, reason := "resultHash mismatch" }, Grpc.Status.ok)
  else if !proofOk then
    ({ accepted := false, reason := "proof invalid" }, Grpc.Status.ok)
  else
    ({ accepted := true, reason := "" }, Grpc.Status.ok)

def handleSubmit (sink : SinkBackend) (req : SubmitRequest) :
    IO (SubmitAck × Grpc.Status) := do
  let (ref, message) ← sink.submit req.receipt
  return ({ ok := true, ref, message }, Grpc.Status.ok)

def handleProve (req : ProveRequest) : ProveResponse × Grpc.Status :=
  -- Without raw rules on ProveRequest, use empty rulesRaw → default allow list.
  (proveLocal ByteArray.empty req, Grpc.Status.ok)

def mkIntegratedServer (store : JobStore) (sink : SinkBackend) (policy : ServerPolicy)
    (trustProofOk : Bool) (includeProve : Bool := true) : Grpc.Server :=
  Id.run do
    let mut s := Grpc.Server.empty
    s := registerTeeExecute s (handleExecute store none (some sink))
    s := registerTeeGetReceipt s (handleGetReceipt store)
    s := registerTeeMeasure s fun req => pure (handleMeasure req)
    s := registerVerifyAccept s fun req => pure (handleAccept policy trustProofOk req)
    s := registerAnchorSinkSubmit s (handleSubmit sink)
    if includeProve then
      s := registerProve s fun req => pure (handleProve req)
    return s

end LeanTee.Services
