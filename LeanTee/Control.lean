/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Guest
import LeanTee.Guests.Registry

namespace LeanTee.Control

structure TenantAcl where
  tenantId : String
  guests : Array String
  deriving Inhabited

structure AclFile where
  tenants : Array TenantAcl := #[]
  /-- Tenants allowed to call LoadProgram. Empty ⇒ no extra LoadProgram gate. -/
  loadProgramTenants : Array String := #[]
  /-- Tenants allowed to send Execute.secret_inputs. Empty ⇒ unrestricted when mode=local. -/
  secretInputsTenants : Array String := #[]
  deriving Inhabited

/-- Line formats (see config/acl.example.txt):
- `tenant_id guest_id [guest_id...]`
- `load_program tenant_id [tenant_id...]` — allow-list for LoadProgram
- `secret_inputs tenant_id [tenant_id...]` — allow-list for Execute.secret_inputs
-/
def loadAclFile (path : String) : IO AclFile := do
  let text ← IO.FS.readFile path
  let mut tenants : Array TenantAcl := #[]
  let mut loadProgramTenants : Array String := #[]
  let mut secretInputsTenants : Array String := #[]
  for line in text.splitOn "\n" do
    let t := Guest.trimStr line
    if t.isEmpty || t.startsWith "#" then continue
    let parts := t.splitOn " " |>.map Guest.trimStr |>.filter (· ≠ "")
    match parts with
    | [] => pure ()
    | "load_program" :: rest =>
      for tid in rest do
        if !loadProgramTenants.contains tid then
          loadProgramTenants := loadProgramTenants.push tid
    | "secret_inputs" :: rest =>
      for tid in rest do
        if !secretInputsTenants.contains tid then
          secretInputsTenants := secretInputsTenants.push tid
    | tenant :: rest =>
      let guests := rest.toArray.filter fun g => (Guests.findBuiltin g).isSome
      tenants := tenants.push { tenantId := tenant, guests }
  return { tenants, loadProgramTenants, secretInputsTenants }

def aclAllows (acl : AclFile) (tenant guestId : String) : Bool :=
  if acl.tenants.isEmpty then true
  else
    match acl.tenants.find? (·.tenantId == tenant) with
    | none => false
    | some t =>
      if t.guests.isEmpty then true
      else t.guests.any (· == guestId)

/-- Empty `loadProgramTenants` ⇒ unrestricted (LoadProgram still needs valid program bytes). -/
def aclAllowsLoadProgram (acl : AclFile) (tenant : String) : Bool :=
  if acl.loadProgramTenants.isEmpty then true
  else acl.loadProgramTenants.any (· == tenant)

/-- Empty `secretInputsTenants` ⇒ unrestricted when confidentiality=local. -/
def aclAllowsSecretInputs (acl : AclFile) (tenant : String) : Bool :=
  if acl.secretInputsTenants.isEmpty then true
  else acl.secretInputsTenants.any (· == tenant)

structure QuotaState where
  windowStartMs : IO.Ref Nat
  countInWindow : IO.Ref Nat
  inflight : IO.Ref Nat

def QuotaState.new : IO QuotaState := do
  pure {
    windowStartMs := ← IO.mkRef 0
    countInWindow := ← IO.mkRef 0
    inflight := ← IO.mkRef 0
  }

def monoMs : IO Nat := IO.monoMsNow

def checkQuota (q : QuotaState) (maxRps maxInflight : Option Nat) : IO (Except String Unit) := do
  match maxInflight with
  | some lim =>
    let n ← q.inflight.get
    if n >= lim then return .error "quota: max inflight"
  | none => pure ()
  match maxRps with
  | none => return .ok ()
  | some lim =>
    let now ← monoMs
    let start ← q.windowStartMs.get
    if now - start >= 1000 then
      q.windowStartMs.set now
      q.countInWindow.set 0
    let c ← q.countInWindow.get
    if c >= lim then return .error "quota: max rps"
    return .ok ()

def beginRequest (q : QuotaState) : IO Unit := do
  q.inflight.modify (· + 1)
  q.countInWindow.modify (· + 1)

def endRequest (q : QuotaState) : IO Unit := do
  q.inflight.modify fun n => if n = 0 then 0 else n - 1

structure Metrics where
  executes : IO.Ref Nat
  accepts : IO.Ref Nat
  rejects : IO.Ref Nat

def Metrics.new : IO Metrics := do
  pure {
    executes := ← IO.mkRef 0
    accepts := ← IO.mkRef 0
    rejects := ← IO.mkRef 0
  }

def Metrics.bumpExecute (m : Metrics) : IO Unit := m.executes.modify (· + 1)
def Metrics.bumpAccept (m : Metrics) (ok : Bool) : IO Unit := do
  if ok then m.accepts.modify (· + 1) else m.rejects.modify (· + 1)

def Metrics.logIfEnabled (m : Metrics) (enabled : Bool) : IO Unit := do
  if !enabled then return
  let e ← m.executes.get
  let a ← m.accepts.get
  let r ← m.rejects.get
  IO.println s!"metrics executes={e} accepts={a} rejects={r}"

def auditLine (path : String) (line : String) : IO Unit := do
  let h ← IO.FS.Handle.mk path .append
  try
    h.putStr (line ++ "\n")
    h.flush
  finally
    h.flush

def checkApiKey (expected presented : Option String) : Except String Unit :=
  match expected with
  | none => .ok ()
  | some want =>
    match presented with
    | some got => if got == want then .ok () else .error "unauthorized: bad api key"
    | none => .error "unauthorized: missing api key"

def writeJobFile (dir jobId resultHashHex : String) : IO Unit := do
  IO.FS.createDirAll dir
  IO.FS.writeFile (System.mkFilePath [dir, s!"{jobId}.ok"]) resultHashHex

def jobFileExists (dir jobId : String) : IO Bool :=
  (System.mkFilePath [dir, s!"{jobId}.ok"]).pathExists

end LeanTee.Control
