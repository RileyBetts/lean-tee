# Contributing to lean-tee

Thank you for helping improve lean-tee. This project is Apache-2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE).
By participating, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- Read [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) for toolchain setup.
- **Mock path** (`lean-tee-v1`) is the default for local iteration — no SP1 required.
- **Production integrity** (`lean-tee-v2`) needs SP1; see [host/README.md](host/README.md).

## Development setup

```bash
git clone https://github.com/RileyBetts/lean-tee.git
cd lean-tee
# elan installs Lean 4.32.1 from lean-toolchain
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y
sudo apt-get install -y libssl-dev pkg-config   # Debian/Ubuntu

lake update    # fetches lean-grpc v1.1.0 into .lake/packages
lake build receiptTests teeServer teeClient
./.lake/build/bin/receiptTests
```

Optional sibling checkout of [lean-grpc](https://github.com/RileyBetts/lean-grpc) at `../lean-grpc` is **not** required when using the git dependency above.

## Running tests

**Lean + demos (mock, no SP1):**

```bash
bash scripts/ci.sh
# or the longer CI-equivalent suite:
bash scripts/standalone_demo.sh
bash scripts/adversarial_matrix_demo.sh
bash scripts/cross_impl_golden_demo.sh
```

**Rust:**

```bash
cd host && cargo test -p lean_tee_receipt -p lean_tee_compliance
```

**Python:**

```bash
python3 -m venv .venv && .venv/bin/pip install pytest
PYTHONPATH=clients/python .venv/bin/pytest clients/python/tests -q
```

**SP1 (optional, heavy):**

```bash
bash scripts/sp1_execute_ci.sh          # execute + digest pin (CI-shaped)
bash scripts/sp1_test_careful.sh        # staged; mock prove by default
```

Do not run real CPU `SP1_PROVER=cpu --prove-one` on ≤16 GiB machines without reading [host/README.md](host/README.md).

## Code conventions

- Match existing style in the file you edit (Lean, Rust, shell, proto).
- Keep changes focused; avoid drive-by refactors.
- SPDX header on new first-party source files: `SPDX-License-Identifier: Apache-2.0`
- Wire/API changes must update [`proto/lean_tee/v1/tee.proto`](proto/lean_tee/v1/tee.proto) and [docs/API.md](docs/API.md).
- Crypto or hash changes require golden vector updates in Lean, Rust, and Python tests.

## Pull requests

1. Branch from `main` (or the active integration branch agreed with maintainers).
2. Ensure mock CI paths pass locally when touching receipts, guests, or gRPC.
3. If you change the Lean SP1 guest or runtime patches, run `bash scripts/sp1_execute_ci.sh` locally (and refresh `artifacts/sp1_guest_digests.json` from Linux if digests change). Automatic `sp1-execute` CI is off for now — GH runners lack the compute.
4. Describe **why** in the PR body; link issues if any.
5. Do not commit secrets, `.env` files, `host/target/`, `.cache/`, or editor junk (e.g. `.#`).

## Reporting issues

Use GitHub Issues for bugs and feature requests. For security-sensitive reports, see [SECURITY.md](SECURITY.md).
Please be respectful — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
