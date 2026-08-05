/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Hash
import LeanTee.Guest

/-!
# Lean-specified guest programs

Programs are **specified in Lean** (AST + deterministic bytes + run semantics).
They are **executed** by the measured Lean-compiled SP1 guest (`guest_prog_runtime`).

This is not “upload Lean source to RISC-V”. Lean is the metalanguage; the payload is a
`GuestProg` whose meaning is defined here (and mirrored in `lean_tee_compliance` for mock/host).
-/

namespace LeanTee.GuestProg

/-- Runtime identity (fixed measured interpreter / oracle). -/
def runtimeCodeId : String := "lean-tee/guest_prog_runtime/lean-sp1/v1"
def runtimeGuestId : String := "guest_prog_runtime"

def runtimeCodeHash : ByteArray := Hash.sha256 runtimeCodeId.toUTF8

/-- Hard cap on program bytes at LoadProgram / parse (override via env on server). -/
def defaultMaxProgramBytes : Nat := 65536
/-- Default max input size when program omits `max_input_bytes=`. -/
def defaultMaxInputBytes : Nat := 65536

structure Program where
  /-- Human label (not hashed into semantics beyond serialization). -/
  name : String := ""
  /-- Allowed action names without `action=` prefix (e.g. `vote.yes`). -/
  allow : List String
  /-- Explicit deny list; checked before allow (deny wins). -/
  deny : List String := []
  /-- When true, inputs must contain an `interaction=` line. -/
  requireInteraction : Bool := false
  /-- Optional per-program input size cap (bytes). `none` ⇒ defaultMaxInputBytes. -/
  maxInputBytes : Option Nat := none
  deriving Inhabited
  -- No BEq/Repr: those pull Init.Meta / Syntax specializations into the SP1 link set.

def Program.wireVersion (p : Program) : String :=
  if p.deny.isEmpty && !p.requireInteraction && p.maxInputBytes.isNone then
    "lean-tee-guest-prog/v1"
  else
    "lean-tee-guest-prog/v2"

def Program.allowPrefixes (p : Program) : List String :=
  p.allow.map (fun a => s!"action={a}")

def Program.denyPrefixes (p : Program) : List String :=
  p.deny.map (fun a => s!"action={a}")

def Program.effectiveMaxInput (p : Program) : Nat :=
  p.maxInputBytes.getD defaultMaxInputBytes

/-- Local join — avoids `String.intercalate` (Init.Data.String.Defs → heavy SP1 Init). -/
private def joinSep (sep : String) : List String → String
  | [] => ""
  | x :: xs => xs.foldl (fun acc s => acc ++ sep ++ s) x

/-- Decimal Nat parser without `String.toNat?` / `String.Slice` (heavy Init). -/
private def parseNatDec? (s : String) : Option Nat :=
  if s.isEmpty then none
  else Id.run do
    let mut n : Nat := 0
    let mut i : Nat := 0
    while i < s.length do
      let c := s.get! ⟨i⟩
      let d := c.toNat
      if d < '0'.toNat || d > '9'.toNat then return none
      n := n * 10 + (d - '0'.toNat)
      i := i + 1
    return some n

/-- Decimal digits without `Nat.repr` (SP1 stubbed `Nat.reprFast` historically). -/
private def natToDec (n : Nat) : String :=
  if n == 0 then "0"
  else Id.run do
    let mut digits : List Char := []
    let mut x := n
    while x > 0 do
      digits := Char.ofNat ('0'.toNat + x % 10) :: digits
      x := x / 10
    return String.ofList digits

/-- Canonical UTF-8 serialization (stable; hashed as config). -/
def Program.serialize (p : Program) : ByteArray :=
  Id.run do
    let ver := p.wireVersion
    let allowLine := "allow=" ++ joinSep "," p.allow
    let mut lines : List String := [ver]
    if !p.name.isEmpty then
      lines := lines ++ [s!"name={p.name}"]
    lines := lines ++ [allowLine]
    if !p.deny.isEmpty then
      lines := lines ++ ["deny=" ++ joinSep "," p.deny]
    if p.requireInteraction then
      lines := lines ++ ["require_interaction=true"]
    if let some n := p.maxInputBytes then
      lines := lines ++ ["max_input_bytes=" ++ natToDec n]
    return (joinSep "\n" lines ++ "\n").toUTF8

def Program.hash (p : Program) : ByteArray :=
  Hash.sha256 p.serialize

def parseBoolFlag (s : String) : Except String Bool :=
  match Guest.trimStr s with
  | "true" | "1" | "yes" => pure true
  | "false" | "0" | "no" => pure false
  | other => throw s!"guest prog: bad bool={other}"

/-- Parse canonical bytes. Fail closed on unknown version / empty allow / oversize. -/
def parse (b : ByteArray) (maxProgramBytes : Nat := defaultMaxProgramBytes) : Except String Program := do
  if b.size > maxProgramBytes then
    throw s!"guest prog: program exceeds max_program_bytes={maxProgramBytes}"
  let text ← match String.fromUTF8? b with
    | some s => pure s
    | none => throw "guest prog: not utf-8"
  let lines := text.splitOn "\n" |>.map Guest.trimStr |>.filter (· ≠ "")
  match lines with
  | [] => throw "guest prog: empty"
  | ver :: rest =>
    if ver != "lean-tee-guest-prog/v1" && ver != "lean-tee-guest-prog/v2" then
      throw s!"guest prog: unsupported version={ver}"
    let mut name := ""
    let mut allow : List String := []
    let mut deny : List String := []
    let mut requireInteraction := false
    let mut maxInputBytes : Option Nat := none
    for line in rest do
      if line.startsWith "name=" then
        name := (line.splitOn "name=").getD 1 ""
      else if line.startsWith "allow=" then
        let rest := (line.splitOn "allow=").getD 1 ""
        allow := rest.splitOn "," |>.map Guest.trimStr |>.filter (· ≠ "")
      else if line.startsWith "deny=" then
        let rest := (line.splitOn "deny=").getD 1 ""
        deny := rest.splitOn "," |>.map Guest.trimStr |>.filter (· ≠ "")
      else if line.startsWith "require_interaction=" then
        let rest := (line.splitOn "require_interaction=").getD 1 ""
        requireInteraction ← parseBoolFlag rest
      else if line.startsWith "max_input_bytes=" then
        let rest := Guest.trimStr ((line.splitOn "max_input_bytes=").getD 1 "")
        match parseNatDec? rest with
        | some n => maxInputBytes := some n
        | none => throw s!"guest prog: bad max_input_bytes={rest}"
      else if line.startsWith "#" then
        pure ()
      else
        throw s!"guest prog: bad line={line}"
    if allow.isEmpty then throw "guest prog: empty allow="
    if ver == "lean-tee-guest-prog/v1" then
      if !deny.isEmpty || requireInteraction || maxInputBytes.isSome then
        throw "guest prog: v1 cannot use deny/require_interaction/max_input_bytes"
    pure { name, allow, deny, requireInteraction, maxInputBytes }

def hasInteractionLine (text : String) : Bool :=
  (text.splitOn "\n").any fun line => (Guest.trimStr line).startsWith "interaction="

def run (p : Program) (inputs : ByteArray) : ByteArray :=
  let text := Guest.inputsAsString inputs
  let decision :=
    if inputs.size > p.effectiveMaxInput then
      "deny"
    else if p.requireInteraction && !hasInteractionLine text then
      "deny"
    else if p.denyPrefixes.any (fun pref => text.startsWith pref) then
      "deny"
    else if p.allowPrefixes.any (fun pref => text.startsWith pref) then
      "allow"
    else
      "deny"
  let reason := Hash.sha256 (Hash.concatLenPrefixed #[p.hash, inputs])
  s!"decision={decision}\nreason={Guest.hexEncode reason}\n".toUTF8

/-- Run from raw program bytes (parse then execute). -/
def runBytes (program inputs : ByteArray) (maxProgramBytes : Nat := defaultMaxProgramBytes) :
    Except String ByteArray := do
  let p ← parse program maxProgramBytes
  pure (run p inputs)

end LeanTee.GuestProg
