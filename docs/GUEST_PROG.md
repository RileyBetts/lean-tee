# Lean-specified guest programs on RISC-V

## What this is

Counterparties (or you) supply a **GuestProg** — a small program whose **syntax and semantics are defined in Lean** ([`LeanTee/GuestProg.lean`](../LeanTee/GuestProg.lean)).  
That program is executed by a **fixed measured runtime** (`guest_prog_runtime`) whose RISC-V ELF runs under SP1.

```text
LoadProgram(GuestProg bytes) → program_id
Execute(program_id | program, inputs) → TeeReceipt
  codeHash  = SHA256("lean-tee/guest_prog_runtime/lean-sp1/v1")  // Lean SP1 guest
  configHash = SHA256(program bytes)                              // your Lean-specified program
```

**Not supported:** uploading Lean *source* to compile/run on RISC-V. Lean is the **spec language** for GuestProg; the SP1 guest is the **Lean-compiled** runtime of that format (proven path = SP1 execute/prove of `lean_tee_guest_lean` + public program).

## Wire (gRPC)

| RPC | Role |
| --- | --- |
| `Tee.LoadProgram` | Validate + store program; return `program_id` / hashes |
| `Tee.GetProgram` | Fetch by `program_id` |
| `Tee.Execute` | Set `program` **or** `program_id`; leave legacy `guest_id` empty |
| `Tee.Measure` | Optional `program` → runtime measurement |
| `Prove.Prove` | Pass `program` when `code_hash` is the runtime |

See [`proto/lean_tee/v1/tee.proto`](../proto/lean_tee/v1/tee.proto).

## Program format

### v1 (`lean-tee-guest-prog/v1`)

```
lean-tee-guest-prog/v1
name=optional-label
allow=vote.yes,vote.no
```

Example: [`examples/guest_programs/demo_votes.prog`](../examples/guest_programs/demo_votes.prog).

### v2 (`lean-tee-guest-prog/v2`)

Adds deny-list, interaction gate, and per-program input size:

```
lean-tee-guest-prog/v2
name=demo-votes-v2
allow=vote.yes,vote.no
deny=vote.admin
require_interaction=true
max_input_bytes=4096
```

Semantics:

| Field | Meaning |
| --- | --- |
| `allow=` | Comma-separated actions; inputs starting with `action=<name>` may allow |
| `deny=` | Checked **before** allow (deny wins) |
| `require_interaction=true` | Inputs must include an `interaction=` line |
| `max_input_bytes=N` | Oversized inputs → `decision=deny` |

Serialize prefers **v1** when only `name`/`allow` are set (stable hashes for simple programs); any extended field forces **v2**.

Hard caps (server): `LEAN_TEE_MAX_PROGRAM_BYTES` (default 65536) on LoadProgram / Execute program bytes.

Example: [`examples/guest_programs/demo_votes_v2.prog`](../examples/guest_programs/demo_votes_v2.prog).

## LoadProgram allow-list

ACL file (see [`config/acl.example.txt`](../config/acl.example.txt)):

```
demo … guest_prog_runtime
load_program demo
```

- If any `load_program` lines exist, only listed tenants may call `LoadProgram`.
- If none, LoadProgram is unrestricted (Execute still needs `guest_prog_runtime` ACL when tenants are configured).

## Demo

```bash
bash scripts/guest_prog_demo.sh
# or:
lake build teeServer guestProgClient
# teeServer …
./.lake/build/bin/guestProgClient 127.0.0.1:50071 examples/guest_programs/demo_votes_v2.prog vote.yes
```

## SP1 / production profile

Production integrity is **`lean-tee-v2`** (SP1 host verify). Mock (`lean-tee-v1`) is **CI/demo only** — never the production default.

```bash
# careful local: execute-only + optional one prove
bash scripts/sp1_test_careful.sh
# CI/nightly execute-only gate
bash scripts/sp1_execute_ci.sh
```

Workflow: [`.github/workflows/sp1-execute.yml`](../.github/workflows/sp1-execute.yml) (`workflow_dispatch` only for now; prefer local `scripts/sp1_execute_ci.sh`).

## Honest claims

| Claim | Status |
| --- | --- |
| Lean defines program meaning | Yes (v1 + v2 AST) |
| gRPC to supply program to TEE API | Yes (`LoadProgram` / `Execute.program`) |
| Size limits + LoadProgram tenant ACL | Yes |
| Program runs on SP1 RISC-V interpreter | Yes (same ELF; program as public input) |
| Arbitrary Lean theorems / full Lean kernel on RISC-V | No |
