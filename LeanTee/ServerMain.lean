/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Services
import LeanTee.Control
import LeanTee.GuestProg
import LeanTee.Confidential
import LeanTee.Grpc

def parseHostPort (addr : String) : IO (String × UInt16) := do
  match addr.splitOn ":" with
  | [h, p] =>
    match p.toNat? with
    | some n => pure (h, n.toUInt16)
    | none => throw (IO.userError s!"bad port in {addr}")
  | _ => throw (IO.userError s!"expected host:port, got {addr}")

def loadSink : IO LeanTee.Services.SinkBackend := do
  match ← IO.getEnv "LEAN_TEE_SINK" with
  | some "print" => pure .print
  | some url =>
    if url.startsWith "http://" || url.startsWith "https://" then
      pure (.webhook url)
    else
      let buf ← IO.mkRef (#[] : Array LeanTee.TeeReceipt)
      pure (.memory buf)
  | none =>
    let buf ← IO.mkRef (#[] : Array LeanTee.TeeReceipt)
    pure (.memory buf)

def loadPolicy : IO LeanTee.Services.ServerPolicy := do
  match ← IO.getEnv "LEAN_TEE_POLICY_FILE" with
  | some path => LeanTee.Services.loadPolicyFile path
  | none => pure {}

def parseNatEnv (name : String) : IO (Option Nat) := do
  match ← IO.getEnv name with
  | none => pure none
  | some s =>
    match s.toNat? with
    | some n => pure (some n)
    | none => pure none

def loadControl : IO LeanTee.Services.ServerControl := do
  let quotas ← LeanTee.Control.QuotaState.new
  let metrics ← LeanTee.Control.Metrics.new
  let acl ← match ← IO.getEnv "LEAN_TEE_ACL_FILE" with
    | some path => LeanTee.Control.loadAclFile path
    | none => pure {}
  let tenant := (← IO.getEnv "LEAN_TEE_TENANT").getD "demo"
  let apiKey ← IO.getEnv "LEAN_TEE_API_KEY"
  -- Server expects clients to present the same key via env mirrored at process start
  -- (lean-grpc h2c has no app metadata gate in v1 demos).
  let presentedKey := apiKey
  let auditPath ← IO.getEnv "LEAN_TEE_AUDIT_FILE"
  let jobDir ← IO.getEnv "LEAN_TEE_JOB_DIR"
  let maxRps ← parseNatEnv "LEAN_TEE_MAX_RPS"
  let maxInflight ← parseNatEnv "LEAN_TEE_MAX_INFLIGHT"
  let metricsEnabled := (← IO.getEnv "LEAN_TEE_METRICS") == some "1"
  -- Production default: lean-tee-v2. Mock (v1) is CI/demo only — never ship as prod hero.
  let defaultProfile := (← IO.getEnv "LEAN_TEE_DEFAULT_PROFILE").getD "lean-tee-v2"
  let maxProgramBytes :=
    match ← parseNatEnv "LEAN_TEE_MAX_PROGRAM_BYTES" with
    | some n => n
    | none => LeanTee.GuestProg.defaultMaxProgramBytes
  let confidentiality :=
    LeanTee.Confidential.parseMode ((← IO.getEnv "LEAN_TEE_CONFIDENTIALITY").getD "off")
  let sealedWorkerBin ← IO.getEnv "LEAN_TEE_SEALED_WORKER"
  if confidentiality == .local && sealedWorkerBin.isNone then
    IO.println "WARN: LEAN_TEE_CONFIDENTIALITY=local but LEAN_TEE_SEALED_WORKER unset"
  return {
    apiKey
    presentedKey
    tenant
    acl
    auditPath
    jobDir
    maxRps
    maxInflight
    metricsEnabled
    maxProgramBytes
    defaultProfile
    confidentiality
    sealedWorkerBin
    quotas
    metrics
  }

/--
Integrated Tee + Verify + AnchorSink on h2c.
If `LEAN_TEE_PROVE_ADDR=host:port` is set, dials remote `Prove` (e.g. Rust host).
Otherwise registers in-process Lean mock Prove.

Env: see docs/ENTERPRISE.md and docs/SLA.md.
-/
def main : IO Unit := do
  let port : UInt16 :=
    match ← IO.getEnv "LEAN_TEE_PORT" with
    | some s => match s.toNat? with | some n => n.toUInt16 | none => 50071
    | none => 50071
  let store ← LeanTee.Services.JobStore.new
  let progStore ← LeanTee.Services.ProgramStore.new
  let sink ← loadSink
  let policy ← loadPolicy
  let ctrl ← loadControl
  let trustProofOk := (← IO.getEnv "LEAN_TEE_TRUST_PROOF_OK") == some "1"
  IO.println s!"lean-tee profile={ctrl.defaultProfile} tenant={ctrl.tenant} max_program_bytes={ctrl.maxProgramBytes} confidentiality={LeanTee.Confidential.modeToString ctrl.confidentiality}"
  if ctrl.defaultProfile == "lean-tee-v1" then
    IO.println "WARN: lean-tee-v1 (mock) is CI/demo only — do not use as production default"
  if ctrl.confidentiality == .local then
    IO.println "NOTE: confidentiality=local is process isolation — not Nitro / hardware sealed RAM"
  match ← IO.getEnv "LEAN_TEE_PROVE_ADDR" with
  | some addr =>
    let (host, p) ← parseHostPort addr
    let ch ← Grpc.Channel.connectH2c host p
    let prove : LeanTee.Grpc.ProveStub := { channel := ch }
    let mut s := Grpc.Server.empty
    s := LeanTee.Grpc.registerTeeExecute s
      (LeanTee.Services.handleExecute store progStore ctrl (some prove) (some sink))
    s := LeanTee.Grpc.registerTeeGetReceipt s (LeanTee.Services.handleGetReceipt store ctrl)
    s := LeanTee.Grpc.registerTeeMeasure s fun req =>
      pure (LeanTee.Services.handleMeasure req ctrl.maxProgramBytes)
    s := LeanTee.Grpc.registerTeeLoadProgram s (LeanTee.Services.handleLoadProgram progStore ctrl)
    s := LeanTee.Grpc.registerTeeGetProgram s (LeanTee.Services.handleGetProgram progStore)
    s := LeanTee.Grpc.registerVerifyAccept s (LeanTee.Services.handleAccept policy ctrl trustProofOk)
    s := LeanTee.Grpc.registerAnchorSinkSubmit s (LeanTee.Services.handleSubmit sink)
    IO.println s!"lean-tee server 127.0.0.1:{port.toNat} (Prove → {host}:{p.toNat})"
    Grpc.Server.serveH2c s { host := "127.0.0.1", port }
  | none =>
    if ctrl.defaultProfile == "lean-tee-v2" then
      IO.println "WARN: lean-tee-v2 without LEAN_TEE_PROVE_ADDR uses in-process mock Prove — wire SP1 prove_server for production"
    let s := LeanTee.Services.mkIntegratedServer store progStore sink policy ctrl trustProofOk true
    IO.println s!"lean-tee server 127.0.0.1:{port.toNat} (in-process Prove)"
    Grpc.Server.serveH2c s { host := "127.0.0.1", port }
