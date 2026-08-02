# lean-tee host — SP1 RISC-V Prove path

Requires [SP1](https://docs.succinct.xyz/docs/sp1/getting-started/install) (`sp1up` → `cargo prove`, version **6.3.1** aligned with this workspace).

## Layout

| Crate | Role |
| --- | --- |
| `compliance_lib` | Shared compliance logic (aligned with `LeanTee.Guest`) |
| `guest` | **SP1 RISC-V zkVM guest ELF** (`lean_tee_guest`) |
| `prove_server` | gRPC `Prove` + `sp1_smoke` binary |

## Install toolchain (once)

```bash
curl -L https://sp1.succinct.xyz | bash
source ~/.bashrc   # or: export PATH="$HOME/.sp1/bin:$PATH"
sp1up
cargo prove --version   # expect sp1 ~6.3.x
```

## Thorough SP1 test (careful / low OOM risk)

CPU proving on a 16GB laptop previously locked the machine (~80%+ RAM). Prefer staged tests:

```bash
export PATH="$HOME/.sp1/bin:$PATH"
cd .. && bash scripts/sp1_test_careful.sh          # execute (cpu) + prove (mock) + Lean e2e
SP1_PROVE_HEAVY=1 bash scripts/sp1_test_careful.sh # adds ONE real CPU prove (watch free -h)
```

Or manually:

```bash
SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only   # all 3 cases, RISC-V guest
SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0 # SDK prove/verify path
# SP1_PROVER=cpu ./target/release/sp1_smoke --prove-one 0  # heavy — only if you have free RAM
```

## Prove gRPC (for Lean Tee)

```bash
SP1_PROVER=cpu LEAN_TEE_PROVE_PORT=50072 \
  cargo run -p lean_tee_prove_server --release --bin prove_server
# Lean: LEAN_TEE_PROVE_ADDR=127.0.0.1:50072 teeServer
```

Dev-only mock (no zkVM): `LEAN_TEE_PROVE_MODE=mock`.

## Processor stack

- Guest ISA target: SP1 RISC-V (`sp1-zkvm` 6.3.1 / Hypercube-era toolchain)
- Guest ELF interprets optional **Lean-specified GuestProg** bytes (see [docs/GUEST_PROG.md](../docs/GUEST_PROG.md))
- Lean FV of full RISC-V / SP1 extractors remains a non-goal; Lean defines GuestProg + Accept checkers
