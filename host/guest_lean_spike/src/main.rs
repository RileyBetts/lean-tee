// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Phase-0 SP1 guest: call Lean-compiled UInt32 exports (C from Lean IR).
//! Not the production compliance guest — spike only.
#![no_main]
sp1_zkvm::entrypoint!(main);

unsafe extern "C" {
    static lean_tee_sp1_hello_tag: u32;
    fn lean_tee_sp1_add(a: u32, b: u32) -> u32;
}

pub fn main() {
    let a: u32 = sp1_zkvm::io::read();
    let b: u32 = sp1_zkvm::io::read();
    let sum = unsafe { lean_tee_sp1_add(a, b) };
    let tag = unsafe { lean_tee_sp1_hello_tag };
    sp1_zkvm::io::commit(&tag);
    sp1_zkvm::io::commit(&sum);
}
