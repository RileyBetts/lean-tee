// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Phase-1 SP1 guest: Lean-compiled compliance entry (`lean_tee_guest_run`).
#![no_main]
extern crate alloc;

sp1_zkvm::entrypoint!(main);

mod sp1_malloc;

unsafe extern "C" {
    /// C bridge → Lean `lean_tee_guest_run`. Caller frees `*out_bytes` with `free`.
    fn lean_tee_sp1_guest_run(
        config_hash: *const u8,
        config_hash_len: usize,
        inputs: *const u8,
        inputs_len: usize,
        program: *const u8,
        program_len: usize,
        out_bytes: *mut *mut u8,
        out_len: *mut usize,
    ) -> i32;
}

pub fn main() {
    let config_hash: [u8; 32] = sp1_zkvm::io::read();
    let inputs: Vec<u8> = sp1_zkvm::io::read();
    let program: Vec<u8> = sp1_zkvm::io::read();

    let mut out_ptr: *mut u8 = core::ptr::null_mut();
    let mut out_len: usize = 0;
    let rc = unsafe {
        lean_tee_sp1_guest_run(
            config_hash.as_ptr(),
            config_hash.len(),
            inputs.as_ptr(),
            inputs.len(),
            program.as_ptr(),
            program.len(),
            &mut out_ptr,
            &mut out_len,
        )
    };
    let outputs = if rc != 0 || out_ptr.is_null() {
        b"decision=deny\nreason=guest_error\n".to_vec()
    } else {
        let slice = unsafe { core::slice::from_raw_parts(out_ptr, out_len) };
        let v = slice.to_vec();
        unsafe {
            sp1_malloc::free(out_ptr);
        }
        v
    };
    sp1_zkvm::io::commit_slice(&outputs);
}
