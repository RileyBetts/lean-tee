# lean-tee

Lean 4–specified **zkTEE** (integrity-first): measured guest execution, SHA-256 hashed receipts, and **lean-grpc** APIs so anchor chains can accept or cheaply reject adversarial results.

Not a confidentiality enclave (no Nitro sealing in v1).

## Layout

| Path | Role |
| --- | --- |
| `LeanTee/` | Hash, receipts, guest model, protobuf codecs, gRPC stubs, services |
| `proto/lean_tee/v1/` | Normative `.proto` |
| `Tests/` | Receipt unit tests + gRPC loopback |
| `docs/` | Threat model + API |

## Dependencies

- Sibling [lean-grpc](../lean-grpc) (`v4.32.1`)
- OpenSSL (`libssl-dev`, `pkg-config`)

```bash
lake build receiptTests teeServer teeClient teeLoopback
./.lake/build/bin/receiptTests
./.lake/build/bin/teeLoopback
```

## Quick demo

```bash
./.lake/build/bin/teeServer   # LEAN_TEE_PORT=50071
# CLI client (JSON hex receipt for Anchor Strict demos):
./.lake/build/bin/teeClient 127.0.0.1:50071 vote.yes /path/to/rules.txt
# gRPC: Tee.Execute / Verify.AcceptReceipt / AnchorSink.Submit
```

Allowed demo actions: `vote.yes|vote.no`, `supplier.register`, `purchaser.approve|reject`, `trade.submit`.

## Status

- [x] Receipt hashing + `acceptReceipt`
- [x] lean-grpc Tee / Prove / Verify / AnchorSink
- [x] Compliance guest (single path) + Lean/Rust mock proofs
- [x] Rust `prove_server` + RISC-V **guest crate** (`host/guest`, SP1-ready)
- [x] `teeClient` CLI for live Execute (Anchor Strict live path)
- [ ] SP1 Hypercube prove enabled in CI (`--features sp1` needs `cargo prove`)
- [x] Anchor Chain Strict Mode adapter (sibling `anchor-chain` branch `feature/strict-mode-lean-tee`)

## RISC-V / SP1

The processor path lives under [`host/`](host/README.md): shared compliance lib, SP1 guest crate, tonic Prove server. CI runs the guest logic via the Rust Prove service (mock `proof_ref` until SP1 toolchain is available).
