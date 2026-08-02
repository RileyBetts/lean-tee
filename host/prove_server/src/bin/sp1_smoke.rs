//! SP1 smoke tests for the compliance guest.
//!
//! Prefer staged runs to avoid OOM on laptops:
//! ```bash
//! SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only
//! SP1_PROVER=cpu ./target/release/sp1_smoke --prove-one 0
//! ```

use lean_tee_compliance::{code_hash, run_compliance, sha256};
use sha2::{Digest, Sha256};
use sp1_sdk::{
    blocking::{ProveRequest, Prover, ProverClient},
    include_elf, Elf, ProvingKey, SP1Stdin,
};

const ELF: Elf = include_elf!("lean_tee_guest");

fn main() {
    sp1_sdk::utils::setup_logger();
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    let args: Vec<String> = std::env::args().skip(1).collect();
    let execute_only = args.iter().any(|a| a == "--execute-only");
    let prove_one = args
        .windows(2)
        .find(|w| w[0] == "--prove-one")
        .and_then(|w| w[1].parse::<usize>().ok());

    let rules = b"rules=vote.yes,vote.no";
    let config_hash = sha256(rules);
    let cases: &[(&[u8], &str)] = &[
        (b"action=vote.yes\n", "allow"),
        (b"action=vote.no\n", "allow"),
        (b"action=transfer.funds\n", "deny"),
    ];

    let client = ProverClient::from_env();
    println!("code_hash={}", hex::encode(code_hash()));
    println!(
        "mode={} execute_only={} prove_one={:?}",
        std::env::var("SP1_PROVER").unwrap_or_default(),
        execute_only,
        prove_one
    );

    if !execute_only {
        println!("ELF setup…");
    }
    let pk = if execute_only {
        None
    } else {
        Some(client.setup(ELF).expect("setup"))
    };

    let indices: Vec<usize> = if let Some(i) = prove_one {
        vec![i]
    } else {
        (0..cases.len()).collect()
    };

    for i in indices {
        let (inputs, expect_decision) = cases[i];
        let expected = run_compliance(&config_hash, inputs);
        assert!(
            std::str::from_utf8(&expected)
                .unwrap()
                .starts_with(&format!("decision={expect_decision}")),
            "native expectation"
        );

        let mut stdin = SP1Stdin::new();
        stdin.write(&config_hash);
        stdin.write(&inputs.to_vec());

        let (pv, report) = client
            .execute(ELF, stdin.clone())
            .run()
            .unwrap_or_else(|e| panic!("execute case {i}: {e}"));
        let outputs = pv.as_slice().to_vec();
        assert_eq!(outputs, expected, "SP1 public values != native guest logic");
        println!(
            "case {i}: execute OK cycles={} decision={expect_decision}",
            report.total_instruction_count()
        );

        if execute_only {
            continue;
        }

        let pk = pk.as_ref().expect("pk");
        println!("case {i}: starting prove (watch memory)…");
        let proof = client
            .prove(pk, stdin)
            .run()
            .unwrap_or_else(|e| panic!("prove case {i}: {e}"));
        client
            .verify(&proof, pk.verifying_key(), None)
            .unwrap_or_else(|e| panic!("verify case {i}: {e}"));
        let proof_bytes = bincode::serialize(&proof).expect("serialize proof");
        let proof_ref = Sha256::digest(&proof_bytes);
        println!(
            "case {i}: prove+verify OK proof_ref={} proof_bytes={}",
            hex::encode(proof_ref),
            proof_bytes.len()
        );
    }

    println!("sp1_smoke OK");
}
