/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Hash
import LeanTee.Guest

/-!
# Lean-specified guest programs

Programs are **specified in Lean** (AST + deterministic bytes + run semantics).
They are **executed** by the measured `guest_prog_runtime` on SP1 RISC-V (Rust twin).

This is not “upload Lean source to RISC-V”. Lean is the metalanguage; the payload is a
`GuestProg` whose meaning is defined here and mirrored in `lean_tee_compliance`.
-/

namespace LeanTee.GuestProg

/-- Runtime identity (fixed measured interpreter / oracle). -/
def runtimeCodeId : String := "lean-tee/guest_prog_runtime/v1"
def runtimeGuestId : String := "guest_prog_runtime"

def runtimeCodeHash : ByteArray := Hash.sha256 runtimeCodeId.toUTF8

structure Program where
  /-- Human label (not hashed into semantics beyond serialization). -/
  name : String := ""
  /-- Allowed action names without `action=` prefix (e.g. `vote.yes`). -/
  allow : List String
  deriving Inhabited, BEq, Repr

def Program.allowPrefixes (p : Program) : List String :=
  p.allow.map (fun a => s!"action={a}")

/-- Canonical UTF-8 serialization (stable; hashed as config). -/
def Program.serialize (p : Program) : ByteArray :=
  let allowLine :=
    "allow=" ++ String.intercalate "," p.allow
  let body :=
    if p.name.isEmpty then
      s!"lean-tee-guest-prog/v1\n{allowLine}\n"
    else
      s!"lean-tee-guest-prog/v1\nname={p.name}\n{allowLine}\n"
  body.toUTF8

def Program.hash (p : Program) : ByteArray :=
  Hash.sha256 p.serialize

/-- Parse canonical bytes. Fail closed on unknown version / empty allow. -/
def parse (b : ByteArray) : Except String Program := do
  let text ← match String.fromUTF8? b with
    | some s => pure s
    | none => throw "guest prog: not utf-8"
  let lines := text.splitOn "\n" |>.map Guest.trimStr |>.filter (· ≠ "")
  match lines with
  | [] => throw "guest prog: empty"
  | ver :: rest =>
    if ver != "lean-tee-guest-prog/v1" then
      throw s!"guest prog: unsupported version={ver}"
    let mut name := ""
    let mut allow : List String := []
    for line in rest do
      if line.startsWith "name=" then
        name := (line.splitOn "name=").getD 1 ""
      else if line.startsWith "allow=" then
        let rest := (line.splitOn "allow=").getD 1 ""
        allow := rest.splitOn "," |>.map Guest.trimStr |>.filter (· ≠ "")
      else if line.startsWith "#" then
        pure ()
      else
        throw s!"guest prog: bad line={line}"
    if allow.isEmpty then throw "guest prog: empty allow="
    pure { name, allow }

def run (p : Program) (inputs : ByteArray) : ByteArray :=
  let text := Guest.inputsAsString inputs
  let allowed := p.allowPrefixes.any (fun pref => text.startsWith pref)
  let decision := if allowed then "allow" else "deny"
  let reason := Hash.sha256 (Hash.concatLenPrefixed #[p.hash, inputs])
  s!"decision={decision}\nreason={Guest.hexEncode reason}\n".toUTF8

/-- Run from raw program bytes (parse then execute). -/
def runBytes (program inputs : ByteArray) : Except String ByteArray := do
  let p ← parse program
  pure (run p inputs)

end LeanTee.GuestProg
