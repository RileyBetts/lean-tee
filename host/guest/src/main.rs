//! SP1 RISC-V guest: single measured compliance path.
#![no_main]
sp1_zkvm::entrypoint!(main);

pub fn main() {
    let config_hash: [u8; 32] = sp1_zkvm::io::read();
    let inputs: Vec<u8> = sp1_zkvm::io::read();
    let outputs = lean_tee_compliance::run_compliance(&config_hash, &inputs);
    sp1_zkvm::io::commit_slice(&outputs);
}
