// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Phase-1: execute Lean-compiled GuestSp1 compliance path inside SP1 (execute-only).
//!
//! ```bash
//! bash scripts/sp1_lean_runtime_build.sh
//! bash scripts/sp1_lean_guest_build.sh
//! cargo build -p lean_tee_prove_server --release --features sp1 --bin sp1_lean_guest_smoke
//! SP1_PROVER=cpu ./target/release/sp1_lean_guest_smoke
//! ```

use lean_tee_compliance::run_compliance;
use lean_tee_receipt::sha256;
use sp1_sdk::{blocking::{Prover, ProverClient}, include_elf, Elf, SP1Stdin};

const ELF: Elf = include_elf!("lean_tee_guest_lean");

fn main() {
    sp1_sdk::utils::setup_logger();
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    // GuestSp1 uses empty rulesRaw → default allow prefixes (vote.yes / vote.no / …).
    let rules = b"";
    let config_hash = sha256(rules);
    let inputs = b"action=vote.yes\n".to_vec();
    let program: Vec<u8> = Vec::new();
    let expect = run_compliance(&config_hash, &inputs);

    let mut stdin = SP1Stdin::new();
    stdin.write(&config_hash);
    stdin.write(&inputs);
    stdin.write(&program);

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
        "sp1_lean_guest_smoke OK decision starts {:?} cycles={}",
        expect.iter().take(20).map(|&b| b as char).collect::<String>(),
        report.total_instruction_count()
    );
}
