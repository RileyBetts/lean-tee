//! Phase-0: execute Lean-emitted UInt32 exports inside SP1 (no Rust twin semantics).
//!
//! ```bash
//! bash scripts/sp1_lean_spike_sync.sh
//! cargo build -p lean_tee_prove_server --release --features sp1 --bin sp1_lean_spike_smoke
//! SP1_PROVER=cpu ./target/release/sp1_lean_spike_smoke
//! ```

use sp1_sdk::{blocking::{Prover, ProverClient}, include_elf, Elf, SP1Stdin};

const ELF: Elf = include_elf!("lean_tee_guest_lean_spike");

fn main() {
    sp1_sdk::utils::setup_logger();
    if std::env::var_os("SP1_PROVER").is_none() {
        std::env::set_var("SP1_PROVER", "cpu");
    }

    let a: u32 = 40;
    let b: u32 = 2;
    let expect_sum = a.wrapping_add(b);
    let expect_tag: u32 = 0x4c53_5031; // LSP1

    let mut stdin = SP1Stdin::new();
    stdin.write(&a);
    stdin.write(&b);

    let client = ProverClient::from_env();
    let (pv, report) = client
        .execute(ELF, stdin)
        .run()
        .unwrap_or_else(|e| panic!("lean spike execute failed: {e}"));

    // Public values: tag then sum (each committed as u32).
    let slice = pv.as_slice();
    assert!(
        slice.len() >= 8,
        "public values too short: {} bytes",
        slice.len()
    );
    let tag = u32::from_le_bytes(slice[0..4].try_into().unwrap());
    let sum = u32::from_le_bytes(slice[4..8].try_into().unwrap());
    assert_eq!(tag, expect_tag, "hello tag mismatch");
    assert_eq!(sum, expect_sum, "lean_tee_sp1_add mismatch");

    println!(
        "sp1_lean_spike_smoke OK tag={tag:#x} sum={sum} cycles={}",
        report.total_instruction_count()
    );
}
