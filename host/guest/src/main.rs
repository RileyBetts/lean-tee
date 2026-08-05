// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! SP1 RISC-V guest: compliance path + Lean-specified GuestProg runtime.
#![no_main]
sp1_zkvm::entrypoint!(main);

pub fn main() {
    let config_hash: [u8; 32] = sp1_zkvm::io::read();
    let inputs: Vec<u8> = sp1_zkvm::io::read();
    let program: Vec<u8> = sp1_zkvm::io::read();
    let outputs = lean_tee_compliance::run_measured(&config_hash, &inputs, &program)
        .unwrap_or_else(|_| b"decision=deny\nreason=guest_error\n".to_vec());
    sp1_zkvm::io::commit_slice(&outputs);
}
