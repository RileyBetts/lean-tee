// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Phase-1: execute Lean-compiled GuestSp1 compliance path inside SP1 (execute-only).

use lean_tee_compliance::{code_hash_for, run_measured, COMPLIANCE};
use lean_tee_receipt::{sha256, CryptoSuite};
use sp1_sdk::{
    blocking::{Prover, ProverClient},
    include_elf, Elf, SP1Stdin,
};

const ELF: Elf = include_elf!("lean_tee_guest_lean");

fn main() {
    sp1_sdk::utils::setup_logger();
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    let suite = CryptoSuite::Sha256Mock;
    let code = code_hash_for(&COMPLIANCE, suite);
    let rules = b"allow=vote.yes,vote.no\n";
    let config_hash = sha256(rules);
    let inputs = b"action=vote.yes\n".to_vec();
    let program: Vec<u8> = Vec::new();
    let expect = run_measured(&code, &config_hash, &inputs, &program, rules).expect("native");

    let mut stdin = SP1Stdin::new();
    stdin.write(&code);
    stdin.write(&config_hash);
    stdin.write(&inputs);
    stdin.write(&program);
    stdin.write(&rules.to_vec());

    let client = ProverClient::from_env();
    let (pv, report) = client
        .execute(ELF, stdin)
        .run()
        .unwrap_or_else(|e| panic!("lean guest execute failed: {e}"));

    let got = pv.as_slice();
    assert_eq!(
        got,
        expect.as_slice(),
        "Lean SP1 guest output mismatch\n got={}\nwant={}",
        String::from_utf8_lossy(got),
        String::from_utf8_lossy(&expect)
    );

    println!(
        "sp1_lean_guest_smoke OK cycles={}",
        report.total_instruction_count()
    );
}
