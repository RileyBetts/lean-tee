// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

fn main() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(feature = "sp1")]
    {
        // Measured guest: Lean-compiled ELF (Phase 3). Optional Rust twin: LEAN_TEE_BUILD_RUST_GUEST=1.
        if std::env::var_os("LEAN_TEE_BUILD_RUST_GUEST").is_some() {
            sp1_build::build_program("../guest");
            println!("cargo:rerun-if-changed=../guest");
        }
        sp1_build::build_program("../guest_lean_spike");
        println!("cargo:rerun-if-changed=../guest_lean_spike");
        println!("cargo:rerun-if-changed=../guest_lean_spike/c");
        sp1_build::build_program("../guest_lean_mid");
        println!("cargo:rerun-if-changed=../guest_lean_mid");
        println!("cargo:rerun-if-changed=../guest_lean_mid/c");
        sp1_build::build_program("../guest_lean");
        println!("cargo:rerun-if-changed=../guest_lean");
        println!("cargo:rerun-if-changed=../lean_sp1_runtime");
        println!("cargo:rerun-if-changed=../lean_sp1_init_min");
    }

    let protoc = protoc_bin_vendored::protoc_bin_path()?;
    std::env::set_var("PROTOC", &protoc);
    let proto = "../../proto/lean_tee/v1/tee.proto";
    println!("cargo:rerun-if-changed={proto}");
    tonic_prost_build::configure()
        .build_client(false)
        .build_server(true)
        .compile_protos(&[proto], &["../../proto"])?;
    Ok(())
}
