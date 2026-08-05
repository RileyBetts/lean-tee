// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

fn main() {
    println!("cargo:rerun-if-changed=c/lean_sp1_spike.c");
    // SP1 guest C needs riscv64-unknown-elf-gcc (`sp1up --c-toolchain`).
    // sp1_build usually injects CC_riscv64im_succinct_zkvm_elf; set a fallback
    // when this crate is built directly.
    if std::env::var_os("CC_riscv64im_succinct_zkvm_elf").is_none() {
        let fallback = std::env::var_os("HOME")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| std::path::PathBuf::from("/"))
            .join(".sp1/bin/riscv64-unknown-elf-gcc");
        if fallback.exists() {
            std::env::set_var("CC_riscv64im_succinct_zkvm_elf", &fallback);
        }
    }
    cc::Build::new()
        .file("c/lean_sp1_spike.c")
        .warnings(false)
        .compile("lean_sp1_spike");
}
