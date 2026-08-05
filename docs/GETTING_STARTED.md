# Getting started

This guide gets you from a fresh clone to a **working mock demo** in under fifteen minutes. Production SP1 integrity (`lean-tee-v2`) is covered at the end.

## What you need

| Tool | Version / notes |
| --- | --- |
| [Lean 4](https://leanprover.github.io/lean4/doc/setup.html) (elan) | **4.32.1** — pinned in [`lean-toolchain`](../lean-toolchain) |
| OpenSSL dev | `libssl-dev` + `pkg-config` (host Lake build links `-lssl`) |
| Rust (optional) | Stable — for `host/` crates and clients |
| Python 3 (optional) | Stdlib client; `pytest` for tests |
| [SP1](https://docs.succinct.xyz/docs/sp1/getting-started/install) (optional) | **6.3.1** — only for `lean-tee-v2` prove path |

**Not required:** AWS Nitro, Anchor Chain checkout, or a sibling `lean-grpc` directory. Lake fetches [lean-grpc](https://github.com/RileyBetts/lean-grpc) **v1.0.0** via git when you run `lake update`.

## 1. Clone and build (mock path)

```bash
git clone https://github.com/RileyBetts/lean-tee.git
cd lean-tee

# Install elan + Lean 4.32.1 if needed
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf \
  | sh -s -- -y --default-toolchain leanprover/lean4:v4.32.1

sudo apt-get install -y libssl-dev pkg-config   # Debian/Ubuntu; adjust on macOS

lake update
lake build receiptTests teeServer teeClient teeLoopback
./.lake/build/bin/receiptTests
```

## 2. Run the standalone demo

Starts `teeServer`, executes a vote via the Lean client, verifies with the Python twin, and rejects a forged receipt:

```bash
bash scripts/standalone_demo.sh
```

Other mock demos (no SP1):

```bash
bash scripts/adversarial_matrix_demo.sh   # Lean + Rust + Python tamper matrix
bash scripts/guest_prog_demo.sh
bash scripts/prove_mock_loopback_demo.sh  # teeServer ↔ Rust prove_server (mock)
```

## 3. Call the API from your code

**Python (local twin — no server):**

```python
from lean_tee import execute_local, accept_receipt

rules = b"allow=vote.yes,vote.no\n"
receipt = execute_local("vote.yes", rules, interaction_id="demo-1")
ok, reason = accept_receipt(receipt)
assert ok, reason
```

**Python (live gRPC)** — set `LEAN_TEE_ADDR=127.0.0.1:50071` while `teeServer` runs; see [clients/python/README.md](../clients/python/README.md).

**Rust** — see [clients/rust/README.md](../clients/rust/README.md).

**Wire contract** — [proto/lean_tee/v1/tee.proto](../proto/lean_tee/v1/tee.proto) and [API.md](API.md).

## 4. Production path (`lean-tee-v2` + SP1)

Mock prove is **CI/demo only**. For production integrity:

1. Install SP1: `curl -L https://sp1up.succinct.xyz | bash && sp1up && sp1up --c-toolchain`
2. Build host: `cd host && cargo build -p lean_tee_prove_server --release --features sp1`
3. Smoke: `bash scripts/sp1_execute_ci.sh` (execute + digest pin)
4. Run `prove_server` with `SP1_PROVER=cpu` and point `teeServer` at it:

```bash
export LEAN_TEE_DEFAULT_PROFILE=lean-tee-v2
export LEAN_TEE_PROVE_ADDR=127.0.0.1:50072
# prove_server in one terminal; teeServer in another
```

Pin counterparties to published digests in [`artifacts/sp1_guest_digests.json`](../artifacts/sp1_guest_digests.json). Plain-English SP1 background: [sp1-integrity-crib-sheet.html](sp1-integrity-crib-sheet.html).

Details: [host/README.md](../host/README.md), [LEAN_SP1_GUEST.md](LEAN_SP1_GUEST.md).

## 5. Configuration cheat sheet

| Variable | Purpose |
| --- | --- |
| `LEAN_TEE_PORT` | teeServer listen port (default 50071 in demos) |
| `LEAN_TEE_DEFAULT_PROFILE` | `lean-tee-v2` (default / SP1) or `lean-tee-v1` (mock demos) |
| `LEAN_TEE_PROVE_ADDR` | Required for v2 — `host:port` of SP1 `prove_server` |
| `LEAN_TEE_ALLOW_MOCK_V2` | `1` allows v2 profile with in-process mock (demos only) |
| `LEAN_TEE_TRUST_PROOF_OK` | `1` allows Accept of foreign SP1 receipts when client sets `proof_ok` |
| `LEAN_TEE_GUESTS_FILE` | Path to guest registry JSON (default `config/guests/registry.json`) |
| `LEAN_TEE_API_KEY` | Optional shared API key (fail closed if set) |
| `LEAN_TEE_ACL_FILE` | Tenant / guest ACL — see [ENTERPRISE.md](ENTERPRISE.md) |

## 6. Reservoir (Lean package index)

[Reservoir](https://reservoir.lean-lang.org/) indexes public Lean packages automatically when:

- The GitHub repo is **public** (not a fork)
- Root [`lake-manifest.json`](../lake-manifest.json) is committed (git-pinned deps)
- GitHub detects an **OSI-approved** license (Apache-2.0)
- The repo has at least **2 stars**

This repo declares Reservoir metadata in [`lakefile.lean`](../lakefile.lean) (`license`, `licenseFiles`, `keywords`, `description`). After open-sourcing, allow a few days for indexing; if missing, file an issue on [leanprover/reservoir](https://github.com/leanprover/reservoir/issues).

**Note:** Reservoir build bots may fail if OpenSSL headers are unavailable on their runners — that affects build badges, not inclusion. Local `lake build` remains the source of truth.

## Next reading

- [PRODUCT.md](PRODUCT.md) — scope and guarantees
- [VS_NITRO.md](VS_NITRO.md) — what this is *not*
- [THREAT_MODEL.md](THREAT_MODEL.md) — trust boundaries
- [CONTRIBUTING.md](../CONTRIBUTING.md) — patches and tests
