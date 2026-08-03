/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Hash
import LeanTee.Guest

/-!
# Local confidentiality (sealed worker)

Optional `LEAN_TEE_CONFIDENTIALITY=local`: secret bytes are handed to a local sealed
worker process and never enter PublicIO. Not a hardware TEE / not Nitro.
-/

namespace LeanTee.Confidential

inductive Mode where
  | off
  | local
  deriving BEq, Repr, Inhabited

def parseMode (s : String) : Mode :=
  match Guest.trimStr s with
  | "local" => .local
  | _ => .off

def modeToString : Mode → String
  | .off => "off"
  | .local => "local"

/-- PublicIO inputs: original public framing + secret_digest line (never raw secret). -/
def publicInputsWithDigest (publicInputs : ByteArray) (secretDigestHex : String) : ByteArray :=
  let base := Guest.inputsAsString publicInputs
  let base' :=
    if base.isEmpty || base.endsWith "\n" then base else base ++ "\n"
  (base' ++ s!"secret_digest={secretDigestHex}\n").toUTF8

/-- Fail closed: public outputs must not contain the raw secret UTF-8 (when decodable). -/
def outputsLookSafe (outputs secret : ByteArray) : Bool :=
  if secret.isEmpty then true
  else
    match String.fromUTF8? secret with
    | none => true
    | some s =>
      if s.isEmpty then true
      else
        let o := Guest.inputsAsString outputs
        !((o.splitOn s).length > 1)

def encodeU32Be (n : Nat) : ByteArray :=
  let n := n.toUInt32
  ByteArray.mk #[
    ((n >>> 24) &&& 0xff).toUInt8,
    ((n >>> 16) &&& 0xff).toUInt8,
    ((n >>> 8) &&& 0xff).toUInt8,
    (n &&& 0xff).toUInt8
  ]

def encodeBlob (payload : ByteArray) : ByteArray :=
  encodeU32Be payload.size ++ payload

structure SealedResult where
  outputs : ByteArray
  secretDigest : ByteArray
  deriving Inhabited

/--
Spawn sealed worker with `--hex-out`: binary stdin (public||secret||extra), ASCII stdout.
extra = GuestProg program bytes, or empty when secret holds compliance rules.
-/
def runSealedWorkerHex (bin guestId : String) (publicInputs secretInputs extra : ByteArray) :
    IO (Except String SealedResult) := do
  let stdinPayload :=
    encodeBlob publicInputs ++ encodeBlob secretInputs ++ encodeBlob extra
  let proc ← IO.Process.spawn {
    cmd := bin
    args := #["--hex-out", guestId]
    stdin := .piped
    stdout := .piped
    stderr := .piped
  }
  try
    proc.stdin.write stdinPayload
    proc.stdin.flush
  catch _ => pure ()
  let stdout ← proc.stdout.readToEnd
  let stderr ← proc.stderr.readToEnd
  let exit ← proc.wait
  if exit != 0 then
    return .error s!"sealed worker exit={exit} err={Guest.trimStr stderr}"
  let lines := stdout.splitOn "\n" |>.map Guest.trimStr |>.filter (· ≠ "")
  match lines with
  | "OK" :: rest =>
    let mut outHex := ""
    let mut digHex := ""
    for line in rest do
      if line.startsWith "outputs_hex=" then
        outHex := (line.splitOn "outputs_hex=").getD 1 ""
      else if line.startsWith "digest_hex=" then
        digHex := (line.splitOn "digest_hex=").getD 1 ""
    if outHex.isEmpty || digHex.isEmpty then
      return .error "sealed worker: missing hex fields"
    match Guest.hexDecode outHex, Guest.hexDecode digHex with
    | some outputs, some digest =>
      if digest.size != 32 then return .error "sealed worker: digest not 32 bytes"
      return .ok { outputs, secretDigest := digest }
    | _, _ => return .error "sealed worker: bad hex"
  | _ => return .error "sealed worker: bad stdout"

end LeanTee.Confidential
