# lean-tee API

Wire contract: [`proto/lean_tee/v1/tee.proto`](../proto/lean_tee/v1/tee.proto)  
Transport: [lean-grpc](https://github.com/RileyBetts/lean-grpc) (h2c locally; TLS/mTLS for real adapters)

## Services

| Service | Methods |
| --- | --- |
| `lean_tee.v1.Tee` | `Execute`, `GetReceipt`, `Measure` |
| `lean_tee.v1.Prove` | `Prove` |
| `lean_tee.v1.Verify` | `AcceptReceipt` |
| `lean_tee.v1.AnchorSink` | `Submit` |

Lean stubs: `LeanTee.Grpc`. Pure accept logic: `LeanTee.TeeReceipt.acceptReceipt`.

## Guest model

Single measured path (no separate TEE processes): compliance operator logic in `LeanTee.Guest.runCompliance`.  
v1 uses a **mock proof**; production will swap `Prove` for SP1 Hypercube while keeping the same protos and `resultHash`.
