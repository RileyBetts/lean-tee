// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Phase-2: Lean GuestProg path inside SP1 (execute-only), vs Rust `run_measured`.
use lean_tee_compliance::{code_hash_for, run_measured, GUEST_PROG_RUNTIME};
use lean_tee_receipt::{sha256, CryptoSuite};
use sp1_sdk::{
    blocking::{Prover, ProverClient},
    include_elf, Elf, SP1Stdin,
};

const ELF: Elf = include_elf!("lean_tee_guest_lean");

fn smoke_one(label: &str, program: &[u8], inputs: &[u8]) {
    let suite = CryptoSuite::Sha256Mock;
    let code = code_hash_for(&GUEST_PROG_RUNTIME, suite);
    let config_hash = sha256(program);
    let rules: &[u8] = b"";
    let expect = run_measured(&code, &config_hash, inputs, program, rules).expect("rust run_measured");

    let mut stdin = SP1Stdin::new();
    stdin.write(&code);
    stdin.write(&config_hash);
    stdin.write(&inputs.to_vec());
    stdin.write(&program.to_vec());
    stdin.write(&rules.to_vec());

    let (pv, report) = ProverClient::from_env()
        .execute(ELF, stdin)
        .run()
        .unwrap_or_else(|e| panic!("lean GuestProg execute failed ({label}): {e}"));

    let got = pv.as_slice();
    assert_eq!(
        got,
        expect.as_slice(),
        "Lean SP1 GuestProg mismatch ({label})\n got={}\nwant={}",
        String::from_utf8_lossy(got),
        String::from_utf8_lossy(&expect)
    );
    println!(
        "sp1_lean_guestprog_smoke OK {label} cycles={}",
        report.total_instruction_count()
    );
}

fn main() {
    sp1_sdk::utils::setup_logger();
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    let v1 = b"lean-tee-guest-prog/v1\nname=demo-votes\nallow=vote.yes,vote.no\n";
    smoke_one("v1-allow", v1, b"action=vote.yes\n");
    smoke_one("v1-deny", v1, b"action=trade.submit\n");

    let v2 = b"lean-tee-guest-prog/v2\nname=demo-v2\nallow=vote.yes\ndeny=vote.admin\nrequire_interaction=true\nmax_input_bytes=128\n";
    smoke_one("v2-allow", v2, b"action=vote.yes\ninteraction=cli\n");
    smoke_one("v2-miss-interaction", v2, b"action=vote.yes\n");
    smoke_one("v2-deny-wins", v2, b"action=vote.admin\ninteraction=cli\n");
}
