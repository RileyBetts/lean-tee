// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Mid-tier SP1 guest: Lean mix over a short word list + fixed Lean rounds.
//! Init-free — not the production compliance guest.
#![no_main]
sp1_zkvm::entrypoint!(main);

unsafe extern "C" {
    static lean_tee_sp1_mid_tag: u32;
    fn lean_tee_sp1_mid_step(acc: u32, x: u32) -> u32;
    fn lean_tee_sp1_mid_rounds(seed: u32, n: u32) -> u32;
}

/// Max words folded in the guest (keeps cycle count laptop-friendly).
const MAX_WORDS: u32 = 32;
/// Extra Lean-side rounds after the fold.
const EXTRA_ROUNDS: u32 = 24;

pub fn main() {
    let n_raw: u32 = sp1_zkvm::io::read();
    let n = n_raw.min(MAX_WORDS);
    let mut acc = unsafe { lean_tee_sp1_mid_tag };
    let mut i = 0u32;
    while i < n {
        let x: u32 = sp1_zkvm::io::read();
        acc = unsafe { lean_tee_sp1_mid_step(acc, x) };
        i += 1;
    }
    // Drain any unread words if host sent more than MAX_WORDS (defensive).
    while i < n_raw {
        let _: u32 = sp1_zkvm::io::read();
        i += 1;
    }
    let out = unsafe { lean_tee_sp1_mid_rounds(acc, EXTRA_ROUNDS) };
    let tag = unsafe { lean_tee_sp1_mid_tag };
    sp1_zkvm::io::commit(&tag);
    sp1_zkvm::io::commit(&out);
}
