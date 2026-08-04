//! SP1 smoke for the **measured** Lean guest (`lean_tee_guest_lean`).
//!
//! Covers compliance (empty program) and GuestProg (non-empty program).
//! Prefer staged runs to avoid OOM on laptops:
//! ```bash
//! SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only
//! SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0
//! SP1_PROVER=cpu ./target/release/sp1_smoke --prove-one 0   # heavy
//! ```

use lean_tee_compliance::{code_hash, run_measured};
use lean_tee_receipt::sha256;
use sha2::{Digest, Sha256};
use sp1_sdk::{
    blocking::{ProveRequest, Prover, ProverClient},
    include_elf, Elf, ProvingKey, SP1Stdin,
};

const ELF: Elf = include_elf!("lean_tee_guest_lean");

struct Case {
    label: &'static str,
    /// Rules body for compliance; ignored when `program` is non-empty.
    rules: &'static [u8],
    inputs: &'static [u8],
    program: &'static [u8],
    expect_decision: &'static str,
}

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

    let v1 = b"lean-tee-guest-prog/v1\nname=demo-votes\nallow=vote.yes,vote.no\n";
    let v2 = b"lean-tee-guest-prog/v2\nname=demo-v2\nallow=vote.yes\ndeny=vote.admin\nrequire_interaction=true\nmax_input_bytes=128\n";

    let cases: &[Case] = &[
        Case {
            label: "compliance-allow-yes",
            rules: b"rules=vote.yes,vote.no",
            inputs: b"action=vote.yes\n",
            program: b"",
            expect_decision: "allow",
        },
        Case {
            label: "compliance-allow-no",
            rules: b"rules=vote.yes,vote.no",
            inputs: b"action=vote.no\n",
            program: b"",
            expect_decision: "allow",
        },
        Case {
            label: "compliance-deny",
            rules: b"rules=vote.yes,vote.no",
            inputs: b"action=transfer.funds\n",
            program: b"",
            expect_decision: "deny",
        },
        Case {
            label: "guestprog-v1-allow",
            rules: b"",
            inputs: b"action=vote.yes\n",
            program: v1,
            expect_decision: "allow",
        },
        Case {
            label: "guestprog-v1-deny",
            rules: b"",
            inputs: b"action=trade.submit\n",
            program: v1,
            expect_decision: "deny",
        },
        Case {
            label: "guestprog-v2-allow",
            rules: b"",
            inputs: b"action=vote.yes\ninteraction=cli\n",
            program: v2,
            expect_decision: "allow",
        },
    ];

    let client = ProverClient::from_env();
    println!("code_hash={}", hex::encode(code_hash()));
    println!(
        "mode={} execute_only={} prove_one={:?} cases={}",
        std::env::var("SP1_PROVER").unwrap_or_default(),
        execute_only,
        prove_one,
        cases.len()
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
        assert!(i < cases.len(), "prove-one index {i} out of range 0..{}", cases.len());
        vec![i]
    } else {
        (0..cases.len()).collect()
    };

    for i in indices {
        let c = &cases[i];
        let config_hash = if c.program.is_empty() {
            sha256(c.rules)
        } else {
            sha256(c.program)
        };
        let expected = run_measured(&config_hash, c.inputs, c.program)
            .unwrap_or_else(|e| panic!("native run_measured {}: {e}", c.label));
        assert!(
            std::str::from_utf8(&expected)
                .unwrap()
                .starts_with(&format!("decision={}", c.expect_decision)),
            "native expectation {}",
            c.label
        );

        let mut stdin = SP1Stdin::new();
        stdin.write(&config_hash);
        stdin.write(&c.inputs.to_vec());
        stdin.write(&c.program.to_vec());

        let (pv, report) = client
            .execute(ELF, stdin.clone())
            .run()
            .unwrap_or_else(|e| panic!("execute {}: {e}", c.label));
        let outputs = pv.as_slice().to_vec();
        assert_eq!(
            outputs, expected,
            "SP1 public values != native ({})",
            c.label
        );
        println!(
            "case {i} {}: execute OK cycles={} decision={}",
            c.label,
            report.total_instruction_count(),
            c.expect_decision
        );

        if execute_only {
            continue;
        }

        let pk = pk.as_ref().expect("pk");
        println!("case {i} {}: starting prove (watch memory)…", c.label);
        let proof = client
            .prove(pk, stdin)
            .run()
            .unwrap_or_else(|e| panic!("prove {}: {e}", c.label));
        client
            .verify(&proof, pk.verifying_key(), None)
            .unwrap_or_else(|e| panic!("verify {}: {e}", c.label));
        let proof_bytes = bincode::serialize(&proof).expect("serialize proof");
        let proof_ref = Sha256::digest(&proof_bytes);
        println!(
            "case {i} {}: prove+verify OK proof_ref={} proof_bytes={}",
            c.label,
            hex::encode(proof_ref),
            proof_bytes.len()
        );
    }

    println!("sp1_smoke OK");
}
