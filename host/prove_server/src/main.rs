//! `lean_tee.v1.Prove` — SP1 RISC-V zkVM prove/verify (default).
//!
//! Env:
//! - `LEAN_TEE_PROVE_PORT` (default 50072)
//! - `SP1_PROVER` — `cpu` (default for local) | `mock` | network modes per SP1 docs
//! - `LEAN_TEE_PROVE_MODE=mock` — skip zkVM; Lean-compatible mock proof (dev only)

use lean_tee_compliance::{code_hash, mock_proof, run_compliance};
use sha2::{Digest, Sha256};
use tonic::{transport::Server, Request, Response, Status};
use tracing::{info, warn};

pub mod pb {
    tonic::include_proto!("lean_tee.v1");
}

use pb::prove_server::{Prove, ProveServer};
use pb::{Measurement, ProveRequest, ProveResponse};

#[derive(Default)]
struct ProveSvc;

#[tonic::async_trait]
impl Prove for ProveSvc {
    async fn prove(&self, req: Request<ProveRequest>) -> Result<Response<ProveResponse>, Status> {
        let req = req.into_inner();
        let m = req
            .measurement
            .ok_or_else(|| Status::invalid_argument("measurement required"))?;
        if m.code_hash != code_hash() {
            return Err(Status::invalid_argument(format!(
                "unsupported code_hash (expected {})",
                hex::encode(code_hash())
            )));
        }
        if m.config_hash.len() != 32 {
            return Err(Status::invalid_argument("config_hash must be 32 bytes"));
        }

        let (outputs, proof_ref) = if mock_mode() {
            warn!("LEAN_TEE_PROVE_MODE=mock — not a zk proof");
            let outputs = run_compliance(&m.config_hash, &req.inputs);
            let proof = mock_proof(&m.code_hash, &m.config_hash, &req.inputs, &outputs);
            (outputs, proof.to_vec())
        } else {
            prove_sp1(&m, &req.inputs)
                .map_err(|e| Status::internal(format!("SP1 prove failed: {e}")))?
        };

        Ok(Response::new(ProveResponse {
            outputs,
            proof_ref,
        }))
    }
}

fn mock_mode() -> bool {
    matches!(
        std::env::var("LEAN_TEE_PROVE_MODE").as_deref(),
        Ok("mock")
    )
}

fn prove_sp1(m: &Measurement, inputs: &[u8]) -> Result<(Vec<u8>, Vec<u8>), Box<dyn std::error::Error>> {
    use sp1_sdk::{
        blocking::{ProveRequest, Prover, ProverClient},
        include_elf, Elf, ProvingKey, SP1Stdin,
    };

    const ELF: Elf = include_elf!("lean_tee_guest");

    let mut stdin = SP1Stdin::new();
    let mut cfg = [0u8; 32];
    cfg.copy_from_slice(&m.config_hash);
    stdin.write(&cfg);
    stdin.write(&inputs.to_vec());

    let client = ProverClient::from_env();

    // Execute to obtain public outputs and cycle report.
    let (public_values, report) = client.execute(ELF, stdin.clone()).run()?;
    let outputs = public_values.as_slice().to_vec();
    info!(
        cycles = report.total_instruction_count(),
        outputs_len = outputs.len(),
        "SP1 execute OK"
    );

    let pk = client.setup(ELF)?;
    let proof = client.prove(&pk, stdin).run()?;
    client.verify(&proof, pk.verifying_key(), None)?;

    let proof_bytes = bincode::serialize(&proof)?;
    let proof_ref = Sha256::digest(&proof_bytes).to_vec();
    info!(proof_ref = %hex::encode(&proof_ref), "SP1 prove+verify OK");
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

    // Prefer local CPU prover unless caller set SP1_PROVER.
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    let port: u16 = std::env::var("LEAN_TEE_PROVE_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(50072);
    let addr = format!("127.0.0.1:{port}").parse()?;
    info!(
        %addr,
        sp1_prover = ?std::env::var("SP1_PROVER").ok(),
        mock = mock_mode(),
        "lean-tee Prove server (SP1 RISC-V)"
    );

    Server::builder()
        .add_service(ProveServer::new(ProveSvc))
        .serve(addr)
        .await?;
    Ok(())
}
