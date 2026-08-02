//! Thin tonic client for `lean_tee.v1` Tee + Prove.

pub mod pb {
    tonic::include_proto!("lean_tee.v1");
}

pub use lean_tee_receipt::{
    bind_interaction, code_hash, mock_proof, result_hash, verify_mock_proof, verify_result_hash,
    PROFILE_V1, PROFILE_V2,
};

use pb::prove_client::ProveClient;
use pb::tee_client::TeeClient;
use pb::{ExecuteRequest, MeasureRequest, ProveRequest};
use tonic::transport::Channel;

pub async fn connect_tee(addr: &str) -> Result<TeeClient<Channel>, tonic::transport::Error> {
    let endpoint = if addr.starts_with("http") {
        addr.to_string()
    } else {
        format!("http://{addr}")
    };
    TeeClient::connect(endpoint).await
}

pub async fn connect_prove(addr: &str) -> Result<ProveClient<Channel>, tonic::transport::Error> {
    let endpoint = if addr.starts_with("http") {
        addr.to_string()
    } else {
        format!("http://{addr}")
    };
    ProveClient::connect(endpoint).await
}

pub async fn execute_action(
    client: &mut TeeClient<Channel>,
    action: &str,
    rules: &[u8],
) -> Result<pb::TeeReceipt, tonic::Status> {
    let inputs = format!("action={action}\n").into_bytes();
    let resp = client
        .execute(ExecuteRequest {
            guest_id: Vec::new(),
            config_hash: rules.to_vec(),
            inputs,
            nonce: Vec::new(),
            submit_to_sink: false,
        })
        .await?
        .into_inner();
    resp.receipt
        .ok_or_else(|| tonic::Status::internal("missing receipt"))
}

pub async fn measure(
    client: &mut TeeClient<Channel>,
    rules: &[u8],
) -> Result<pb::Measurement, tonic::Status> {
    let resp = client
        .measure(MeasureRequest {
            config_hash: rules.to_vec(),
        })
        .await?
        .into_inner();
    resp.measurement
        .ok_or_else(|| tonic::Status::internal("missing measurement"))
}

pub async fn prove_mock(
    client: &mut ProveClient<Channel>,
    measurement: pb::Measurement,
    inputs: Vec<u8>,
) -> Result<pb::ProveResponse, tonic::Status> {
    Ok(client
        .prove(ProveRequest {
            measurement: Some(measurement),
            inputs,
        })
        .await?
        .into_inner())
}
