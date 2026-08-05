// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! SP1 smoke for the **measured** Lean guest (`lean_tee_guest_lean`).
//!
//! Covers compliance (empty program) and GuestProg (non-empty program).
//! Prefer staged runs to avoid OOM on laptops:
//! ```bash
//! SP1_PROVER=cpu ./target/release/sp1_smoke --execute-only
//! SP1_PROVER=mock ./target/release/sp1_smoke --prove-one 0
//! SP1_PROVER=cpu ./target/release/sp1_smoke --prove-one 0   # heavy
//! SP1_PROVER=cpu ./target/release/sp1_smoke --print-digests --write-digests ../../artifacts/sp1_guest_digests.json
//! ```

use lean_tee_compliance::{
    code_hash, code_hash_for, run_measured, COMPLIANCE, GUEST_PROG_RUNTIME, VOTING,
};
use lean_tee_receipt::{sha256, CryptoSuite};
use sha2::{Digest, Sha256};
use sp1_sdk::{
    blocking::{ProveRequest, Prover, ProverClient},
    include_elf, Elf, HashableKey, ProvingKey, SP1Stdin,
};
use std::path::PathBuf;

const ELF: Elf = include_elf!("lean_tee_guest_lean");
const GUEST_NAME: &str = "lean_tee_guest_lean";
const SP1_CRATE_VERSION: &str = "6.3.1";

struct Case {
    label: &'static str,
    /// Builtin guest code hash (compliance / voting / guest_prog_runtime).
    code: [u8; 32],
    /// Rules body for compliance; ignored when `program` is non-empty.
    rules: &'static [u8],
    inputs: &'static [u8],
    program: &'static [u8],
    expect_decision: &'static str,
}

struct GuestDigests {
    code_hash_hex: String,
    elf_sha256_hex: String,
    vk_hash_bytes_hex: String,
    vk_bytes32: String,
    elf_len: usize,
}

fn compute_digests(pk: &impl ProvingKey) -> GuestDigests {
    let elf_sha = Sha256::digest(&*ELF);
    let vk = pk.verifying_key();
    GuestDigests {
        code_hash_hex: hex::encode(code_hash()),
        elf_sha256_hex: hex::encode(elf_sha),
        vk_hash_bytes_hex: hex::encode(vk.hash_bytes()),
        vk_bytes32: vk.bytes32(),
        elf_len: ELF.len(),
    }
}

fn digests_json(d: &GuestDigests) -> String {
    // Hand-rolled JSON — avoid a new serde_json dependency on the smoke binary.
    format!(
        "{{\n  \"guest\": \"{GUEST_NAME}\",\n  \"profile\": \"lean-tee-v2\",\n  \"code_id_example\": \"lean-tee/compliance_operator/lean-sp1/v1\",\n  \"code_hash\": \"{}\",\n  \"elf_sha256\": \"{}\",\n  \"elf_bytes\": {},\n  \"vk_hash_bytes\": \"{}\",\n  \"vk_bytes32\": \"{}\",\n  \"sp1_version\": \"{SP1_CRATE_VERSION}\",\n  \"note\": \"Wire Measurement remains codeHash+configHash (logical code_id). elf_sha256 / vk_* pin the SP1 executable for counterparties and host verify.\"\n}}\n",
        d.code_hash_hex, d.elf_sha256_hex, d.elf_len, d.vk_hash_bytes_hex, d.vk_bytes32
    )
}

fn print_and_maybe_write_digests(d: &GuestDigests, write_path: Option<&PathBuf>) {
    println!("elf_sha256={}", d.elf_sha256_hex);
    println!("elf_bytes={}", d.elf_len);
    println!("vk_hash_bytes={}", d.vk_hash_bytes_hex);
    println!("vk_bytes32={}", d.vk_bytes32);
    let json = digests_json(d);
    if let Some(path) = write_path {
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).expect("create digests dir");
            }
        }
        std::fs::write(path, &json).expect("write digests json");
        println!("wrote digests {}", path.display());
    }
}

fn main() {
    sp1_sdk::utils::setup_logger();
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    let args: Vec<String> = std::env::args().skip(1).collect();
    let execute_only = args.iter().any(|a| a == "--execute-only");
    let print_digests = args.iter().any(|a| a == "--print-digests");
    let write_digests = args
        .windows(2)
        .find(|w| w[0] == "--write-digests")
        .map(|w| PathBuf::from(&w[1]));
    let digests_requested = print_digests || write_digests.is_some();
    let prove_one = args
        .windows(2)
        .find(|w| w[0] == "--prove-one")
        .and_then(|w| w[1].parse::<usize>().ok());
    // Digests alone (no execute / prove): setup + print/write, then exit.
    let digests_only = digests_requested && !execute_only && prove_one.is_none();

    let suite = CryptoSuite::Sha256Mock;
    let compliance_code = code_hash_for(&COMPLIANCE, suite);
    let voting_code = code_hash_for(&VOTING, suite);
    let prog_code = code_hash_for(&GUEST_PROG_RUNTIME, suite);

    let v1 = b"lean-tee-guest-prog/v1\nname=demo-votes\nallow=vote.yes,vote.no\n";
    let v2 = b"lean-tee-guest-prog/v2\nname=demo-v2\nallow=vote.yes\ndeny=vote.admin\nrequire_interaction=true\nmax_input_bytes=128\n";
    let allow_rules = b"allow=vote.yes,vote.no\n";

    let cases: &[Case] = &[
        Case {
            label: "compliance-allow-yes",
            code: compliance_code,
            rules: allow_rules,
            inputs: b"action=vote.yes\n",
            program: b"",
            expect_decision: "allow",
        },
        Case {
            label: "compliance-allow-no",
            code: compliance_code,
            rules: allow_rules,
            inputs: b"action=vote.no\n",
            program: b"",
            expect_decision: "allow",
        },
        Case {
            label: "compliance-deny",
            code: compliance_code,
            rules: allow_rules,
            inputs: b"action=transfer.funds\n",
            program: b"",
            expect_decision: "deny",
        },
        Case {
            label: "voting-deny-trade",
            code: voting_code,
            rules: b"",
            inputs: b"action=trade.submit\n",
            program: b"",
            expect_decision: "deny",
        },
        Case {
            label: "guestprog-v1-allow",
            code: prog_code,
            rules: b"",
            inputs: b"action=vote.yes\n",
            program: v1,
            expect_decision: "allow",
        },
        Case {
            label: "guestprog-v1-deny",
            code: prog_code,
            rules: b"",
            inputs: b"action=trade.submit\n",
            program: v1,
            expect_decision: "deny",
        },
        Case {
            label: "guestprog-v2-allow",
            code: prog_code,
            rules: b"",
            inputs: b"action=vote.yes\ninteraction=cli\n",
            program: v2,
            expect_decision: "allow",
        },
    ];

    let client = ProverClient::from_env();
    println!("code_hash={}", hex::encode(code_hash()));
    println!(
        "mode={} execute_only={} prove_one={:?} digests={} cases={}",
        std::env::var("SP1_PROVER").unwrap_or_default(),
        execute_only,
        prove_one,
        digests_requested,
        cases.len()
    );

    // Setup when proving, printing digests, or digests-only. Execute-only without digests skips setup.
    let need_setup = !execute_only || digests_requested;
    if need_setup {
        println!("ELF setup…");
    }
    let pk = if need_setup {
        Some(client.setup(ELF).expect("setup"))
    } else {
        None
    };

    if digests_requested {
        let d = compute_digests(pk.as_ref().expect("pk for digests"));
        print_and_maybe_write_digests(&d, write_digests.as_ref());
        if digests_only {
            println!("sp1_smoke digests OK");
            return;
        }
    }

    let indices: Vec<usize> = if let Some(i) = prove_one {
        assert!(i < cases.len(), "prove-one index {i} out of range 0..{}", cases.len());
        vec![i]
    } else {
        (0..cases.len()).collect()
    };

    for i in indices {
        let c = &cases[i];
        let config_hash = if c.program.is_empty() {
            if c.rules.is_empty() {
                sha256(b"")
            } else {
                sha256(c.rules)
            }
        } else {
            sha256(c.program)
        };
        let expected = run_measured(&c.code, &config_hash, c.inputs, c.program, c.rules)
            .unwrap_or_else(|e| panic!("native run_measured {}: {e}", c.label));
        assert!(
            std::str::from_utf8(&expected)
                .unwrap()
                .starts_with(&format!("decision={}", c.expect_decision)),
            "native expectation {}",
            c.label
        );

        let mut stdin = SP1Stdin::new();
        stdin.write(&c.code);
        stdin.write(&config_hash);
        stdin.write(&c.inputs.to_vec());
        stdin.write(&c.program.to_vec());
        stdin.write(&c.rules.to_vec());

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
