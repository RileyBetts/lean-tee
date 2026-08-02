/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Std.Data.HashMap
import LeanTee.Guest
import LeanTee.Guests.Registry
import LeanTee.Control
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

def resolveGuestCodeHash (guestId : ByteArray) : Except String ByteArray :=
  Guests.resolveCodeHash guestId

def resolveGuest (guestId : ByteArray) : Except String Guests.GuestDesc :=
  let id :=
    match String.fromUTF8? guestId with
    | some s => s
    | none => ""
  Guests.resolve id

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

/-- Enterprise runtime knobs (from env in ServerMain). -/
structure ServerControl where
  apiKey : Option String := none
  presentedKey : Option String := none
  tenant : String := "demo"
  acl : Control.AclFile := {}
  auditPath : Option String := none
  jobDir : Option String := none
  maxRps : Option Nat := none
  maxInflight : Option Nat := none
  metricsEnabled : Bool := false
  quotas : Control.QuotaState
  metrics : Control.Metrics

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
    pure ("sink-webhook", s!"queued url={url}")

def proveLocal (g : Guests.GuestDesc) (rulesRaw : ByteArray) (req : ProveRequest) : ProveResponse :=
  let outputs := Guests.runGuest g req.measurement.configHash rulesRaw req.inputs
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
    receiptMeta := {
      version := "v1"
      domain := "lean-tee/v1"
      sinkId := "lean-tee"
      cryptoSuite := suiteSha256Mock
    }
  }

def handleMeasure (req : MeasureRequest) : MeasureResponse × Grpc.Status :=
  match resolveGuestCodeHash req.guestId with
  | .error e => ({ measurement := default }, Grpc.Status.invalidArgument e)
  | .ok codeHash =>
    let m : Measurement := { codeHash, configHash := Hash.sha256 req.configHash }
    ({ measurement := m }, Grpc.Status.ok)

def handleExecute (store : JobStore) (ctrl : ServerControl) (prove? : Option ProveStub)
    (sink? : Option SinkBackend) (req : ExecuteRequest) : IO (ExecuteResponse × Grpc.Status) := do
  match Control.checkApiKey ctrl.apiKey ctrl.presentedKey with
  | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.unauthenticated e)
  | .ok () => pure ()
  let g ← match resolveGuest req.guestId with
    | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.invalidArgument e)
    | .ok g => pure g
  if !Control.aclAllows ctrl.acl ctrl.tenant g.guestId then
    return ({ jobId := "", status := s!"error:forbidden guest_id={g.guestId}" }, Grpc.Status.permissionDenied "acl")
  match ← Control.checkQuota ctrl.quotas ctrl.maxRps ctrl.maxInflight with
  | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.resourceExhausted e)
  | .ok () => pure ()
  Control.beginRequest ctrl.quotas
  try
    Control.Metrics.bumpExecute ctrl.metrics
    let m : Measurement := { codeHash := g.codeHash, configHash := Hash.sha256 req.configHash }
    let proveResp ← match prove? with
      | none => pure (proveLocal g req.configHash { measurement := m, inputs := req.inputs })
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
    if let some dir := ctrl.jobDir then
      Control.writeJobFile dir jobId (Guest.hexEncode receipt.resultHash)
    if req.submitToSink then
      match sink? with
      | none => pure ()
      | some sink =>
        let _ ← sink.submit receipt
        pure ()
    if let some path := ctrl.auditPath then
      Control.auditLine path s!"\{ \"event\":\"execute\", \"guest_id\":\"{g.guestId}\", \"job_id\":\"{jobId}\", \"tenant\":\"{ctrl.tenant}\" }"
    Control.Metrics.logIfEnabled ctrl.metrics ctrl.metricsEnabled
    return ({ jobId, receipt := some receipt, status := "done" }, Grpc.Status.ok)
  finally
    Control.endRequest ctrl.quotas

def handleGetReceipt (store : JobStore) (ctrl : ServerControl) (req : GetReceiptRequest) :
    IO (ExecuteResponse × Grpc.Status) := do
  match ← store.get? req.jobId with
  | some r => return ({ jobId := req.jobId, receipt := some r, status := "done" }, Grpc.Status.ok)
  | none =>
    match ctrl.jobDir with
    | some dir =>
      if ← Control.jobFileExists dir req.jobId then
        return ({ jobId := req.jobId, status := "done" }, Grpc.Status.ok)
      else
        return ({ jobId := req.jobId, status := "pending" }, Grpc.Status.ok)
    | none => return ({ jobId := req.jobId, status := "pending" }, Grpc.Status.ok)

def handleAccept (policy : ServerPolicy) (ctrl : ServerControl) (trustProofOk : Bool)
    (req : AcceptReceiptRequest) : IO (AcceptReceiptResponse × Grpc.Status) := do
  match Control.checkApiKey ctrl.apiKey ctrl.presentedKey with
  | .error e => return ({ accepted := false, reason := e }, Grpc.Status.unauthenticated e)
  | .ok () => pure ()
  let suite := normalizeCryptoSuite req.receipt.receiptMeta.cryptoSuite
  let resp :=
    if !leanHostSupportsSuite suite then
      ({ accepted := false
         reason := s!"unsupported crypto_suite={suite} (Lean host; use lean_tee_receipt for blake3+mock)"
       } : AcceptReceiptResponse)
    else
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
        { accepted := false, reason := "measurement not in policy" }
      else if !req.receipt.hashMatches then
        { accepted := false, reason := "resultHash mismatch" }
      else if !proofOk then
        { accepted := false, reason := "proof invalid" }
      else
        { accepted := true, reason := "" }
  Control.Metrics.bumpAccept ctrl.metrics resp.accepted
  if let some path := ctrl.auditPath then
    Control.auditLine path s!"\{ \"event\":\"accept\", \"accepted\":{resp.accepted}, \"reason\":\"{resp.reason}\", \"tenant\":\"{ctrl.tenant}\", \"result_hash_hex\":\"{Guest.hexEncode req.receipt.resultHash}\" }"
  Control.Metrics.logIfEnabled ctrl.metrics ctrl.metricsEnabled
  return (resp, Grpc.Status.ok)

def handleSubmit (sink : SinkBackend) (req : SubmitRequest) :
    IO (SubmitAck × Grpc.Status) := do
  let (ref, message) ← sink.submit req.receipt
  return ({ ok := true, ref, message }, Grpc.Status.ok)

def handleProve (req : ProveRequest) : ProveResponse × Grpc.Status :=
  -- Prove without guest_id: map codeHash back to builtin guest or compliance.
  let g :=
    match Guests.builtin.find? (fun x => Hash.bytesEq x.codeHash req.measurement.codeHash) with
    | some g => g
    | none => Guests.compliance
  (proveLocal g ByteArray.empty req, Grpc.Status.ok)

def mkIntegratedServer (store : JobStore) (sink : SinkBackend) (policy : ServerPolicy)
    (ctrl : ServerControl) (trustProofOk : Bool) (includeProve : Bool := true) : Grpc.Server :=
  Id.run do
    let mut s := Grpc.Server.empty
    s := registerTeeExecute s (handleExecute store ctrl none (some sink))
    s := registerTeeGetReceipt s (handleGetReceipt store ctrl)
    s := registerTeeMeasure s fun req => pure (handleMeasure req)
    s := registerVerifyAccept s (handleAccept policy ctrl trustProofOk)
    s := registerAnchorSinkSubmit s (handleSubmit sink)
    if includeProve then
      s := registerProve s fun req => pure (handleProve req)
    return s

end LeanTee.Services
