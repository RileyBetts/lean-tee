// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Mid-tier Lean SP1 smoke (Init-free mix + rounds). Laptop-oriented prove path.
//!
//! ```bash
//! bash scripts/sp1_lean_mid_sync.sh
//! cargo build -p lean_tee_prove_server --release --features sp1 --bin sp1_lean_mid_smoke
//! SP1_PROVER=cpu ./target/release/sp1_lean_mid_smoke
//! SP1_PROVER=cpu ./target/release/sp1_lean_mid_smoke --prove
//! ```

use sp1_sdk::{
    blocking::{ProveRequest, Prover, ProverClient},
    include_elf, Elf, ProvingKey, SP1Stdin,
};

const ELF: Elf = include_elf!("lean_tee_guest_lean_mid");
const MID_TAG: u32 = 0x4d49_4431; // MID1
const EXTRA_ROUNDS: u32 = 24;

fn mid_step(acc: u32, x: u32) -> u32 {
    let y = acc ^ x;
    y.wrapping_mul(1_664_525).wrapping_add(1_013_904_223)
}

fn mid_rounds(seed: u32, n: u32) -> u32 {
    let mut a = seed;
    for i in 0..n {
        a = mid_step(a, i);
    }
    a
}

fn expected(words: &[u32]) -> (u32, u32) {
    let mut acc = MID_TAG;
    for &x in words {
        acc = mid_step(acc, x);
    }
    (MID_TAG, mid_rounds(acc, EXTRA_ROUNDS))
}

fn main() {
    sp1_sdk::utils::setup_logger();
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }
    let prove = std::env::args().any(|a| a == "--prove");

    // 16 words — between spike (~5k cycles) and full compliance (~170k).
    let words: [u32; 16] = [
        1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597,
    ];
    let (expect_tag, expect_out) = expected(&words);

    let mut stdin = SP1Stdin::new();
    stdin.write(&(words.len() as u32));
    for w in words {
        stdin.write(&w);
    }

    let client = ProverClient::from_env();
    let (pv, report) = client
        .execute(ELF, stdin.clone())
        .run()
        .unwrap_or_else(|e| panic!("lean mid execute failed: {e}"));

    let slice = pv.as_slice();
    assert!(
        slice.len() >= 8,
        "public values too short: {} bytes",
        slice.len()
    );
    let tag = u32::from_le_bytes(slice[0..4].try_into().unwrap());
    let out = u32::from_le_bytes(slice[4..8].try_into().unwrap());
    assert_eq!(tag, expect_tag, "mid tag mismatch");
    assert_eq!(out, expect_out, "mid digest mismatch");

    println!(
        "sp1_lean_mid_smoke execute OK tag={tag:#x} out={out:#x} cycles={} words={}",
        report.total_instruction_count(),
        words.len()
    );

    if !prove {
        println!("sp1_lean_mid_smoke OK (pass --prove for CPU prove+verify)");
        return;
    }

    println!(
        "starting mid prove (SP1_PROVER={})…",
        std::env::var("SP1_PROVER").unwrap_or_default()
    );
    let pk = client.setup(ELF).expect("mid setup");
    let proof = client
        .prove(&pk, stdin)
        .run()
        .unwrap_or_else(|e| panic!("mid prove failed: {e}"));
    client
        .verify(&proof, pk.verifying_key(), None)
        .unwrap_or_else(|e| panic!("mid verify failed: {e}"));
    println!("sp1_lean_mid_smoke prove+verify OK");
}
