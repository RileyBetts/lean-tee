# Lean-specified guest programs on RISC-V

## What this is

Counterparties (or you) supply a **GuestProg** — a small program whose **syntax and semantics are defined in Lean** ([`LeanTee/GuestProg.lean`](../LeanTee/GuestProg.lean)).  
That program is executed by a **fixed measured runtime** (`guest_prog_runtime`) whose RISC-V ELF runs under SP1.

```text
LoadProgram(GuestProg bytes) → program_id
Execute(program_id | program, inputs) → TeeReceipt
  codeHash  = SHA256("lean-tee/guest_prog_runtime/v1")   // interpreter
  configHash = SHA256(program bytes)                     // your Lean-specified program
```

**Not supported:** uploading Lean *source* to compile/run on RISC-V. Lean is the **spec language** for GuestProg; the SP1 guest is a **Rust interpreter** of that format (proven path = SP1 execute/prove of the interpreter + public program).

## Wire (gRPC)

| RPC | Role |
| --- | --- |
| `Tee.LoadProgram` | Validate + store program; return `program_id` / hashes |
| `Tee.GetProgram` | Fetch by `program_id` |
| `Tee.Execute` | Set `program` **or** `program_id`; leave legacy `guest_id` empty |
| `Tee.Measure` | Optional `program` → runtime measurement |
| `Prove.Prove` | Pass `program` when `code_hash` is the runtime |

See [`proto/lean_tee/v1/tee.proto`](../proto/lean_tee/v1/tee.proto).

## Program format (`lean-tee-guest-prog/v1`)

```
lean-tee-guest-prog/v1
name=optional-label
allow=vote.yes,vote.no
```

Example: [`examples/guest_programs/demo_votes.prog`](../examples/guest_programs/demo_votes.prog).

## Demo

```bash
bash scripts/guest_prog_demo.sh
# or:
lake build teeServer guestProgClient
# teeServer …
./.lake/build/bin/guestProgClient 127.0.0.1:50071 examples/guest_programs/demo_votes.prog vote.yes
```

## SP1

The RISC-V guest reads `(config_hash, inputs, program)`. Non-empty `program` ⇒ interpret GuestProg (and require `config_hash == SHA256(program)`). Empty `program` ⇒ legacy compliance operator.

```bash
# careful SP1 execute (writes empty program for legacy cases)
bash scripts/sp1_test_careful.sh
```

## Honest claims

| Claim | Status |
| --- | --- |
| Lean defines program meaning | Yes |
| gRPC to supply program to TEE API | Yes (`LoadProgram` / `Execute.program`) |
| Program runs on SP1 RISC-V interpreter | Yes (same ELF; program as public input) |
| Arbitrary Lean theorems / full Lean kernel on RISC-V | No |
