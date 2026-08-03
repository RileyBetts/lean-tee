use sp1_sdk::{blocking::{Prover, ProverClient}, include_elf, Elf, SP1Stdin};

const ELF: Elf = include_elf!("lean_tee_guest_lean");

fn main() {
    sp1_sdk::utils::setup_logger();
    std::env::set_var("SP1_PROVER", "cpu");
    let (pv, report) = ProverClient::from_env()
        .execute(ELF, SP1Stdin::new())
        .run()
        .expect("execute");
    let n = i32::from_le_bytes(pv.as_slice()[0..4].try_into().unwrap());
    println!(
        "sp1_lean_init_smoke n={n} cycles={}",
        report.total_instruction_count()
    );
    assert_eq!(n, 11, "obj_once utf8 size");
}
