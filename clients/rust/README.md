# lean-tee Rust client

Thin [tonic](https://github.com/hyperium/tonic) client for `lean_tee.v1.Tee` and `Prove`, plus re-exports from `lean_tee_receipt` for local hash/mock checks.

## Setup

From the repo root:

```bash
cd clients/rust
cargo build
```

Requires a running `teeServer` (and optionally `prove_server`) for live calls.

## Execute (mock server)

```rust
use lean_tee_client::{connect_tee, execute_action};
use lean_tee_receipt::{verify_mock_proof, verify_result_hash};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut client = connect_tee("127.0.0.1:50071").await?;
    let rules = b"allow=vote.yes,vote.no\n";

    let receipt = execute_action(&mut client, "vote.yes", rules).await?;

    // Local verify (mock suite — sha256+mock default)
    let m = receipt.measurement.as_ref().expect("measurement");
    let io = receipt.public_io.as_ref().expect("public_io");
    assert!(verify_result_hash(
        &m.code_hash,
        &m.config_hash,
        &io.inputs,
        &io.outputs,
        &receipt.nonce,
        &receipt.result_hash,
    ));
    assert!(verify_mock_proof(
        &m.code_hash,
        &m.config_hash,
        &io.inputs,
        &io.outputs,
        &receipt.proof_ref,
    ));

    Ok(())
}
```

Start the server first:

```bash
lake build teeServer
LEAN_TEE_PORT=50071 ./.lake/build/bin/teeServer
```

## Measure + Prove (mock prove_server)

```rust
use lean_tee_client::{connect_prove, connect_tee, measure, prove_mock};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let rules = b"allow=vote.yes,vote.no\n";
    let mut tee = connect_tee("127.0.0.1:50071").await?;
    let m = measure(&mut tee, rules).await?;

    let mut prove = connect_prove("127.0.0.1:50072").await?;
    let inputs = b"action=vote.yes\n";
    let _resp = prove_mock(&mut prove, m, inputs.to_vec()).await?;
    Ok(())
}
```

Run mock prove_server with `LEAN_TEE_PROVE_MODE=mock` — see [docs/GETTING_STARTED.md](../../docs/GETTING_STARTED.md).

## SP1 receipts

This crate does not verify SP1 proofs. Use `prove_server` with `SP1_PROVER=cpu` and host-side SP1 verify for `lean-tee-v2`.

## See also

- [host/receipt](../../host/receipt) — shared crypto
- [proto/lean_tee/v1/tee.proto](../../proto/lean_tee/v1/tee.proto)
- [docs/API.md](../../docs/API.md)
