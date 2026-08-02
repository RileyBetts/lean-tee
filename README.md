# lean-tee

**Integrity-first zkTEE** — measured guest execution, SHA-256 hashed receipts, and lean-grpc APIs so chains and verifiers can accept honest results or cheaply reject adversarial ones.

Not a confidentiality enclave (no Nitro / sealed memory).

| Profile | Prove | Verify | Use |
| --- | --- | --- | --- |
| **`lean-tee-v1`** | Mock proof (`SHA256` domain `lean-tee/mock-proof/v1`) | Recompute resultHash + mock proof | Demos, Anchor Strict first cut, CI |
| **`lean-tee-v2`** | SP1 Hypercube RISC-V | Host verifies SP1; never trust client `proof_ok` alone | Production-oriented integrity |

## Quickstart (mock, no SP1)

Requires Lean 4 (`lean-toolchain`), OpenSSL, and a [lean-grpc](https://github.com/RileyBetts/lean-grpc) checkout (git-pinned; see below).

```bash
lake build receiptTests teeServer teeClient teeLoopback
./.lake/build/bin/receiptTests
./scripts/standalone_demo.sh
```

Manual:

```bash
./.lake/build/bin/teeServer          # LEAN_TEE_PORT=50071
echo 'rules=vote.yes,vote.no' > /tmp/rules.txt
./.lake/build/bin/teeClient 127.0.0.1:50071 vote.yes /tmp/rules.txt
```

Rust Prove (mock, no `cargo prove`):

```bash
cd host && cargo build -p lean_tee_prove_server --no-default-features
LEAN_TEE_PROVE_MODE=mock LEAN_TEE_PROVE_PORT=50072 \
  ./target/debug/prove_server
```

## Product contract (`lean-tee-v1`)

- Wire: [`proto/lean_tee/v1/tee.proto`](proto/lean_tee/v1/tee.proto)
- `resultHash` domain: `lean-tee/v1` (length-prefixed SHA-256)
- Mock `proof_ref` domain: `lean-tee/mock-proof/v1`
- Guest code id: `SHA256("lean-tee/compliance_operator/v1")`
- Shared Rust algorithms: crate `lean_tee_receipt` under [`host/receipt`](host/receipt)

See [docs/PRODUCT.md](docs/PRODUCT.md), [docs/API.md](docs/API.md), [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md).

## Layout

| Path | Role |
| --- | --- |
| `LeanTee/` | Spec: hash, receipts, guest, codecs, gRPC services |
| `proto/lean_tee/v1/` | Normative `.proto` |
| `host/receipt` | Shared Rust receipt crypto (Anchor-linkable) |
| `host/compliance_lib` | Guest compliance logic |
| `host/prove_server` | tonic Prove (mock and/or SP1) |
| `host/guest` | SP1 RISC-V guest ELF |
| `clients/python` | Python Execute / AcceptReceipt SDK |
| `clients/rust` | Thin tonic Tee + Prove client |
| `Tests/` | Receipt + gRPC loopbacks |
| `docs/` | Product, API, threat model |
| `scripts/standalone_demo.sh` | Clone-and-run mock gate |

## Dependencies

- [lean-grpc](https://github.com/RileyBetts/lean-grpc) **v1.0.0** as sibling `../lean-grpc` (CI checks out that tag; see [docs/PRODUCT.md](docs/PRODUCT.md))
- OpenSSL (`libssl-dev`, `pkg-config`)
- Optional: SP1 toolchain (`sp1up`) for `lean-tee-v2` / `--features sp1`

## Status

- [x] Receipt hashing + `acceptReceipt`
- [x] lean-grpc Tee / Prove / Verify / AnchorSink
- [x] Shared `lean_tee_receipt` + golden vectors
- [x] Mock-first standalone demo + CI
- [x] Policy / guest registry (compliance operator)
- [x] SP1 prove path + host verify (`lean-tee-v2`)
- [x] Anchor Chain Strict Mode consumer (sibling repo)

## License

Apache-2.0 — see [LICENSE](LICENSE).
