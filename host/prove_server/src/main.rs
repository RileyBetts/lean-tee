//! `lean_tee.v1.Prove` — mock by default; SP1 with `--features sp1`.
//!
//! Env:
//! - `LEAN_TEE_PROVE_PORT` (default 50072)
//! - `LEAN_TEE_PROVE_MODE=mock` — force mock even when SP1 feature is enabled
//! - `SP1_PROVER` — when SP1 enabled (default `cpu`)

use lean_tee_compliance::{
    code_hash_for, mock_proof, resolve_guest_by_code_hash, run_measured, COMPLIANCE,
    GUEST_PROG_RUNTIME, RUNTIME_CODE_ID,
};
use lean_tee_receipt::{sha256, CryptoSuite};
use tonic::{transport::Server, Request, Response, Status};
use tracing::{info, warn};

pub mod pb {
    tonic::include_proto!("lean_tee.v1");
}

use pb::prove_server::{Prove, ProveServer};
use pb::{ProveRequest, ProveResponse};

#[derive(Default)]
struct ProveSvc;

#[tonic::async_trait]
impl Prove for ProveSvc {
    async fn prove(&self, req: Request<ProveRequest>) -> Result<Response<ProveResponse>, Status> {
        let req = req.into_inner();
        let m = req
            .measurement
            .ok_or_else(|| Status::invalid_argument("measurement required"))?;
        if m.code_hash.len() != 32 {
            return Err(Status::invalid_argument("code_hash must be 32 bytes"));
        }
        let suite = CryptoSuite::Sha256Mock;
        let guest = resolve_guest_by_code_hash(&m.code_hash, suite).unwrap_or(&COMPLIANCE);
        if m.config_hash.len() != 32 {
            return Err(Status::invalid_argument("config_hash must be 32 bytes"));
        }
        let mut cfg = [0u8; 32];
        cfg.copy_from_slice(&m.config_hash);

        let (outputs, proof_ref) = if use_mock() {
            warn!(guest = guest.guest_id, "mock Prove — lean-tee-v1 (not a zk proof)");
            let outputs = run_measured(&cfg, &req.inputs, &req.program)
                .map_err(|e| Status::invalid_argument(e))?;
            let proof = mock_proof(&m.code_hash, &m.config_hash, &req.inputs, &outputs);
            (outputs, proof.to_vec())
        } else {
            #[cfg(feature = "sp1")]
            {
                prove_sp1(&m, &req.inputs, &req.program)
                    .map_err(|e| Status::internal(format!("SP1 prove failed: {e}")))?
            }
            #[cfg(not(feature = "sp1"))]
            {
                let _ = (
                    guest,
                    code_hash_for(&COMPLIANCE, suite),
                    GUEST_PROG_RUNTIME,
                    RUNTIME_CODE_ID,
                    sha256,
                );
                return Err(Status::failed_precondition(
                    "SP1 not compiled in; rebuild with --features sp1 or set LEAN_TEE_PROVE_MODE=mock",
                ));
            }
        };

        Ok(Response::new(ProveResponse {
            outputs,
            proof_ref,
        }))
    }
}

fn use_mock() -> bool {
    matches!(
        std::env::var("LEAN_TEE_PROVE_MODE").as_deref(),
        Ok("mock")
    ) || !cfg!(feature = "sp1")
}

#[cfg(feature = "sp1")]
fn prove_sp1(
    m: &pb::Measurement,
    inputs: &[u8],
    program: &[u8],
) -> Result<(Vec<u8>, Vec<u8>), Box<dyn std::error::Error>> {
    use sha2::{Digest, Sha256};
    use sp1_sdk::{
        blocking::{Prover, ProverClient},
        include_elf, Elf, SP1Stdin,
    };

    const ELF: Elf = include_elf!("lean_tee_guest");

    let mut stdin = SP1Stdin::new();
    let mut cfg = [0u8; 32];
    cfg.copy_from_slice(&m.config_hash);
    stdin.write(&cfg);
    stdin.write(&inputs.to_vec());
    stdin.write(&program.to_vec());

    let client = ProverClient::from_env();
    let (public_values, report) = client.execute(ELF, stdin.clone()).run()?;
    let outputs = public_values.as_slice().to_vec();
    info!(
        cycles = report.total_instruction_count(),
        outputs_len = outputs.len(),
        "SP1 execute OK"
    );

    let pk = client.setup(ELF)?;
    let proof = client.prove(&pk, stdin).run()?;
    // Host verify — lean-tee-v2: never skip this before advertising proof_ref.
    client.verify(&proof, pk.verifying_key(), None)?;

    let proof_bytes = bincode::serialize(&proof)?;
    let proof_ref = Sha256::digest(&proof_bytes).to_vec();
    info!(proof_ref = %hex::encode(&proof_ref), "SP1 prove+verify OK (lean-tee-v2)");
    Ok((outputs, proof_ref))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .init();

    if cfg!(feature = "sp1") && std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    let port: u16 = std::env::var("LEAN_TEE_PROVE_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(50072);
    let addr = format!("127.0.0.1:{port}").parse()?;
    info!(
        %addr,
        mock = use_mock(),
        sp1_feature = cfg!(feature = "sp1"),
        "lean-tee Prove server"
    );

    Server::builder()
        .add_service(ProveServer::new(ProveSvc))
        .serve(addr)
        .await?;
    Ok(())
}
