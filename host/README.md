# lean-tee host — SP1 RISC-V Prove path

Requires [SP1](https://docs.succinct.xyz/docs/sp1/getting-started/install) (`sp1up` → `cargo prove`, version **6.3.1** aligned with this workspace).

## Layout

| Crate | Role |
| --- | --- |
| `compliance_lib` | Shared compliance / GuestProg logic (mock + parity) |
| `guest_lean` | **Measured SP1 guest ELF** — Lean→C→RISC-V (`lean_tee_guest_lean`) |
| `guest` | Legacy Rust twin (optional; `LEAN_TEE_BUILD_RUST_GUEST=1`) |
| `prove_server` | gRPC `Prove` + `sp1_smoke` (Lean ELF) |

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
cd .. && bash scripts/sp1_execute_ci.sh            # execute-only + digests (CI / weekly gate)
cd .. && bash scripts/sp1_guest_digest.sh          # ELF/vk digests only → artifacts/
cd .. && bash scripts/sp1_test_careful.sh          # execute (cpu) + prove (mock) + Lean e2e
# Real CPU prove: prefer Actions prove_heavy. Local needs ≥10GiB free or FORCE:
# SP1_PROVE_HEAVY=1 SP1_PROVE_HEAVY_FORCE=1 bash scripts/sp1_test_careful.sh
```

Production profile: `LEAN_TEE_DEFAULT_PROFILE=lean-tee-v2` + `LEAN_TEE_PROVE_ADDR` to this `prove_server`. Without `LEAN_TEE_PROVE_ADDR`, teeServer refuses to start (unless `LEAN_TEE_ALLOW_MOCK_V2=1`). Mock is CI/dev only.

SP1 guest stdin: `code_hash`, `config_hash`, `inputs`, `program`, `rules` — see [docs/LEAN_SP1_GUEST.md](../docs/LEAN_SP1_GUEST.md).

Or manually:

```bash
SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only --print-digests
SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0 # SDK prove/verify path
# Do NOT run SP1_PROVER=cpu --prove-one on ≤16GiB laptops (hard lock / OOM risk).
```

GitHub Actions (`sp1-execute`): schedule = execute + digests; manual `prove_one` = mock prove; `prove_one` + `prove_heavy` = one real CPU prove (use only when the runner has headroom).

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
