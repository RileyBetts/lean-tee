/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import Std.Data.HashMap
import LeanTee.Guest
import LeanTee.GuestProg
import LeanTee.Guests.Registry
import LeanTee.Control
import LeanTee.Confidential
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

/-- Find a receipt previously issued by this server (host-verified SP1 Accept path). -/
def JobStore.findIssued? (self : JobStore) (r : TeeReceipt) : IO Bool := do
  let m ← self.jobs.get
  return m.fold (init := false) fun acc _ stored =>
    acc ||
      (Hash.bytesEq stored.resultHash r.resultHash
        && Hash.bytesEq stored.proofRef r.proofRef
        && Measurement.beq stored.measurement r.measurement
        && Hash.bytesEq stored.publicIO.inputs r.publicIO.inputs
        && Hash.bytesEq stored.publicIO.outputs r.publicIO.outputs)

/-- In-memory store for Lean-specified GuestProg payloads (program_id → bytes). -/
structure ProgramStore where
  programs : IO.Ref (Std.HashMap String ByteArray)

def ProgramStore.new : IO ProgramStore := do
  let programs ← IO.mkRef (∅ : Std.HashMap String ByteArray)
  return { programs }

def ProgramStore.put (self : ProgramStore) (id : String) (prog : ByteArray) : IO Unit := do
  self.programs.modify fun m => m.insert id prog

def ProgramStore.get? (self : ProgramStore) (id : String) : IO (Option ByteArray) := do
  let m ← self.programs.get
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
  /-- Cap for GuestProg bytes at LoadProgram / Execute (default 64 KiB). -/
  maxProgramBytes : Nat := GuestProg.defaultMaxProgramBytes
  /-- Documented profile: lean-tee-v1 (mock) or lean-tee-v2 (SP1). -/
  defaultProfile : String := "lean-tee-v1"
  /-- Optional local confidentiality (off|local). -/
  confidentiality : Confidential.Mode := .off
  /-- Path to `sealed_worker` binary when confidentiality=local. -/
  sealedWorkerBin : Option String := none
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
  let outputs :=
    if g.guestId == GuestProg.runtimeGuestId then
      match GuestProg.runBytes req.program req.inputs with
      | .ok o => o
      | .error _ => "decision=deny\nreason=parse_error\n".toUTF8
    else
      Guests.runGuest g req.measurement.configHash rulesRaw req.inputs
  let proof := Guest.mockProof req.measurement req.inputs outputs
  { outputs, proofRef := proof, cryptoSuite := suiteSha256Mock }

def verifyMockProofOk (r : TeeReceipt) : Bool :=
  Guest.verifyMockProof r.measurement r.publicIO.inputs r.publicIO.outputs r.proofRef

def buildReceipt (m : Measurement) (inputs outputs nonce proofRef : ByteArray)
    (cryptoSuite confidentiality secretDigestHex : String := "") : TeeReceipt :=
  let suite :=
    let t := Guest.trimStr cryptoSuite
    if t.isEmpty then suiteSha256Mock else t
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
      cryptoSuite := suite
      confidentiality
      secretDigestHex
    }
  }

def handleLoadProgram (store : ProgramStore) (ctrl : ServerControl) (req : LoadProgramRequest) :
    IO (LoadProgramResponse × Grpc.Status) := do
  match Control.checkApiKey ctrl.apiKey ctrl.presentedKey with
  | .error e => return ({}, Grpc.Status.unauthenticated e)
  | .ok () => pure ()
  if !Control.aclAllowsLoadProgram ctrl.acl ctrl.tenant then
    return ({}, Grpc.Status.permissionDenied s!"acl: tenant={ctrl.tenant} cannot LoadProgram")
  let raw := req.program.program
  if raw.isEmpty then
    return ({}, Grpc.Status.invalidArgument "empty program")
  if raw.size > ctrl.maxProgramBytes then
    return ({}, Grpc.Status.invalidArgument
      s!"guest prog: program exceeds max_program_bytes={ctrl.maxProgramBytes}")
  match GuestProg.parse raw ctrl.maxProgramBytes with
  | .error e => return ({}, Grpc.Status.invalidArgument e)
  | .ok _ =>
    let h := Hash.sha256 raw
    let id := Guest.hexEncode h
    store.put id raw
    if let some path := ctrl.auditPath then
      Control.auditLine path
        s!"\{ \"event\":\"load_program\", \"tenant\":\"{ctrl.tenant}\", \"program_id\":\"{id}\" }"
    return ({
      programId := id
      programHash := h
      runtimeCodeHash := GuestProg.runtimeCodeHash
      runtimeGuestId := GuestProg.runtimeGuestId
    }, Grpc.Status.ok)

def handleGetProgram (store : ProgramStore) (req : GetProgramRequest) :
    IO (GetProgramResponse × Grpc.Status) := do
  match ← store.get? req.programId with
  | none => return ({}, Grpc.Status.invalidArgument "unknown program_id")
  | some raw =>
    return ({
      program := { program := raw, name := "" }
      programHash := Hash.sha256 raw
    }, Grpc.Status.ok)

def handleMeasure (req : MeasureRequest) (maxProgramBytes : Nat := GuestProg.defaultMaxProgramBytes) :
    MeasureResponse × Grpc.Status :=
  if !req.program.isEmpty then
    match GuestProg.parse req.program maxProgramBytes with
    | .error e => ({ measurement := default }, Grpc.Status.invalidArgument e)
    | .ok _ =>
      let m : Measurement := {
        codeHash := GuestProg.runtimeCodeHash
        configHash := Hash.sha256 req.program
      }
      ({ measurement := m }, Grpc.Status.ok)
  else
    match resolveGuestCodeHash req.guestId with
    | .error e => ({ measurement := default }, Grpc.Status.invalidArgument e)
    | .ok codeHash =>
      let m : Measurement := { codeHash, configHash := Hash.sha256 req.configHash }
      ({ measurement := m }, Grpc.Status.ok)

/-- Resolve program bytes from inline field or ProgramStore. -/
def resolveProgramBytes (store : ProgramStore) (req : ExecuteRequest) :
    IO (Except String (Option ByteArray)) := do
  if !req.program.isEmpty then return .ok (some req.program)
  if !req.programId.isEmpty then
    match ← store.get? req.programId with
    | some p => return .ok (some p)
    | none => return .error s!"unknown program_id={req.programId}"
  return .ok none

def handleExecute (store : JobStore) (progStore : ProgramStore) (ctrl : ServerControl)
    (prove? : Option ProveStub) (sink? : Option SinkBackend) (req : ExecuteRequest) :
    IO (ExecuteResponse × Grpc.Status) := do
  match Control.checkApiKey ctrl.apiKey ctrl.presentedKey with
  | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.unauthenticated e)
  | .ok () => pure ()
  if !req.secretInputs.isEmpty then
    if ctrl.defaultProfile == "lean-tee-v2" then
      return ({ jobId := "", status := "error:confidentiality=local incompatible with lean-tee-v2 (SP1 guest cannot see secrets); use lean-tee-v1" },
        Grpc.Status.invalidArgument "confidentiality vs v2")
    match ctrl.confidentiality with
    | .off =>
      return ({ jobId := "", status := "error:secret_inputs require LEAN_TEE_CONFIDENTIALITY=local" },
        Grpc.Status.invalidArgument "confidentiality off")
    | .local =>
      if !Control.aclAllowsSecretInputs ctrl.acl ctrl.tenant then
        return ({ jobId := "", status := s!"error:acl tenant={ctrl.tenant} cannot send secret_inputs" },
          Grpc.Status.permissionDenied "acl secret_inputs")
  let prog? ← match ← resolveProgramBytes progStore req with
    | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.invalidArgument e)
    | .ok p => pure p
  -- (guest, measurement, programBytes, rulesForProve)
  let (g, m, programBytes, rulesForProve) ← match prog? with
    | some prog =>
      if prog.size > ctrl.maxProgramBytes then
        return ({ jobId := "", status := s!"error:program exceeds max_program_bytes={ctrl.maxProgramBytes}" },
          Grpc.Status.invalidArgument "program too large")
      match GuestProg.parse prog ctrl.maxProgramBytes with
      | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.invalidArgument e)
      | .ok _ =>
        let g := Guests.guestProgRuntime
        let m : Measurement := {
          codeHash := GuestProg.runtimeCodeHash
          configHash := Hash.sha256 prog
        }
        pure (g, m, prog, ByteArray.empty)
    | none =>
      let g ← match resolveGuest req.guestId with
        | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.invalidArgument e)
        | .ok g => pure g
      let configPreimage :=
        if !req.secretInputs.isEmpty && req.configHash.isEmpty then req.secretInputs
        else req.configHash
      let m : Measurement := { codeHash := g.codeHash, configHash := Hash.sha256 configPreimage }
      pure (g, m, ByteArray.empty, configPreimage)
  if !Control.aclAllows ctrl.acl ctrl.tenant g.guestId then
    return ({ jobId := "", status := s!"error:forbidden guest_id={g.guestId}" }, Grpc.Status.permissionDenied "acl")
  match ← Control.checkQuota ctrl.quotas ctrl.maxRps ctrl.maxInflight with
  | .error e => return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.resourceExhausted e)
  | .ok () => pure ()
  Control.beginRequest ctrl.quotas
  try
    Control.Metrics.bumpExecute ctrl.metrics
    -- Resolve public prove path or sealed-worker path (secrets never in PublicIO).
    let sealedOrProve : Except String (ByteArray × ProveResponse × String × String) ← do
      if req.secretInputs.isEmpty then
        let proveReq : ProveRequest := {
          measurement := m
          inputs := req.inputs
          program := programBytes
          rules := rulesForProve
        }
        match prove? with
        | none =>
          pure (.ok (req.inputs, proveLocal g rulesForProve proveReq, "", ""))
        | some stub =>
          match ← stub.Prove proveReq with
          | .error e => pure (.error e)
          | .ok r => pure (.ok (req.inputs, r, "", ""))
      else
        match ctrl.sealedWorkerBin with
        | none => pure (.error "LEAN_TEE_SEALED_WORKER unset")
        | some bin =>
          let extra :=
            if g.guestId == GuestProg.runtimeGuestId then programBytes else ByteArray.empty
          match ← Confidential.runSealedWorkerHex bin g.guestId req.inputs req.secretInputs extra with
          | .error e => pure (.error e)
          | .ok sealed =>
            if !Confidential.outputsLookSafe sealed.outputs req.secretInputs then
              pure (.error "sealed worker outputs leaked secret")
            else
              let digHex := Guest.hexEncode sealed.secretDigest
              let publicInputs := Confidential.publicInputsWithDigest req.inputs digHex
              let proof := Guest.mockProof m publicInputs sealed.outputs
              let proveResp : ProveResponse := {
                outputs := sealed.outputs
                proofRef := proof
                cryptoSuite := suiteSha256Mock
              }
              pure (.ok (publicInputs, proveResp, "local", digHex))
    match sealedOrProve with
    | .error e =>
      return ({ jobId := "", status := s!"error:{e}" }, Grpc.Status.internal e)
    | .ok (publicInputs, proveResp, confMeta, digHex) =>
      let nonce :=
        if req.nonce.isEmpty then Hash.sha256 (Hash.concatLenPrefixed #[publicInputs, m.configHash])
        else req.nonce
      let suite :=
        let t := Guest.trimStr proveResp.cryptoSuite
        if t.isEmpty then suiteSha256Mock else t
      let receipt := buildReceipt m publicInputs proveResp.outputs nonce proveResp.proofRef
        suite confMeta digHex
      if !Confidential.outputsLookSafe receipt.publicIO.inputs req.secretInputs then
        return ({ jobId := "", status := "error:public inputs leaked secret" }, Grpc.Status.internal "secret leak")
      if !Confidential.outputsLookSafe receipt.publicIO.outputs req.secretInputs then
        return ({ jobId := "", status := "error:public outputs leaked secret" }, Grpc.Status.internal "secret leak")
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
        let conf := if confMeta.isEmpty then "off" else confMeta
        Control.auditLine path
          s!"\{ \"event\":\"execute\", \"guest_id\":\"{g.guestId}\", \"job_id\":\"{jobId}\", \"tenant\":\"{ctrl.tenant}\", \"confidentiality\":\"{conf}\" }"
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

def handleAccept (store : JobStore) (policy : ServerPolicy) (ctrl : ServerControl)
    (trustProofOk : Bool) (req : AcceptReceiptRequest) :
    IO (AcceptReceiptResponse × Grpc.Status) := do
  match Control.checkApiKey ctrl.apiKey ctrl.presentedKey with
  | .error e => return ({ accepted := false, reason := e }, Grpc.Status.unauthenticated e)
  | .ok () => pure ()
  let suite := normalizeCryptoSuite req.receipt.receiptMeta.cryptoSuite
  let confReq := Guest.trimStr req.requireConfidentiality
  if !confReq.isEmpty then
    if req.receipt.receiptMeta.confidentiality != confReq then
      return ({ accepted := false
                reason := s!"require_confidentiality={confReq} but receipt has confidentiality={req.receipt.receiptMeta.confidentiality}"
              }, Grpc.Status.ok)
    if confReq == "local" && req.receipt.receiptMeta.secretDigestHex.isEmpty then
      return ({ accepted := false, reason := "require_confidentiality=local needs secret_digest_hex" }, Grpc.Status.ok)
  if !leanHostSupportsSuite suite then
    return ({ accepted := false
              reason := s!"unsupported crypto_suite={suite} (Lean host; use lean_tee_receipt for blake3+mock)"
            }, Grpc.Status.ok)
  let reqPolicy : MeasurementPolicy := {
    allowed := #[{ codeHash := req.policyCodeHash, configHash := req.policyConfigHash }]
  }
  let measurementOk :=
    (req.policyCodeHash.isEmpty && req.policyConfigHash.isEmpty && policy.allows req.receipt.measurement)
    || reqPolicy.allows req.receipt.measurement
    || (policy.entries.isEmpty && !req.policyCodeHash.isEmpty && reqPolicy.allows req.receipt.measurement)
  if !measurementOk then
    let resp := { accepted := false, reason := "measurement not in policy" }
    Control.Metrics.bumpAccept ctrl.metrics false
    return (resp, Grpc.Status.ok)
  if !req.receipt.hashMatches then
    let resp := { accepted := false, reason := "resultHash mismatch" }
    Control.Metrics.bumpAccept ctrl.metrics false
    return (resp, Grpc.Status.ok)
  let mockOk := verifyMockProofOk req.receipt
  let issued ← store.findIssued? req.receipt
  let proofOk :=
    if suite == suiteSha256Mock then
      mockOk
    else if suite == suiteSha256Sp1 then
      -- SP1: accept receipts this host minted after prove_server host-verify, or opt-in trust.
      if issued then true
      else if trustProofOk then req.proofOk
      else false
    else
      false
  let resp : AcceptReceiptResponse :=
    if !proofOk then
      if suite == suiteSha256Sp1 && !issued && !trustProofOk then
        { accepted := false
          reason := "sp1 proof not verified by this host (Execute here first, or LEAN_TEE_TRUST_PROOF_OK=1 after external verify)" }
      else
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
  (proveLocal g req.rules req, Grpc.Status.ok)

def mkIntegratedServer (store : JobStore) (progStore : ProgramStore) (sink : SinkBackend)
    (policy : ServerPolicy) (ctrl : ServerControl) (trustProofOk : Bool)
    (includeProve : Bool := true) : Grpc.Server :=
  Id.run do
    let mut s := Grpc.Server.empty
    s := registerTeeExecute s (handleExecute store progStore ctrl none (some sink))
    s := registerTeeGetReceipt s (handleGetReceipt store ctrl)
    s := registerTeeMeasure s fun req => pure (handleMeasure req ctrl.maxProgramBytes)
    s := registerTeeLoadProgram s (handleLoadProgram progStore ctrl)
    s := registerTeeGetProgram s (handleGetProgram progStore)
    s := registerVerifyAccept s (handleAccept store policy ctrl trustProofOk)
    s := registerAnchorSinkSubmit s (handleSubmit sink)
    if includeProve then
      s := registerProve s fun req => pure (handleProve req)
    return s

end LeanTee.Services
