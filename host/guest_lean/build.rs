use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let root = manifest_dir.join("../..");
    let cache = root.join(".cache/lean-sp1-guest");
    let runtime = root.join(".cache/lean-sp1-runtime/prefix/lib");
    let guest_a = cache.join("libLeanTeeGuest.a");
    let lean_a = runtime.join("libLean.a");

    println!("cargo:rerun-if-changed=../../scripts/sp1_lean_guest_build.sh");
    println!("cargo:rerun-if-changed=../../LeanTee/GuestSp1.lean");
    println!("cargo:rerun-if-changed=../../LeanTee/GuestProg.lean");
    println!("cargo:rerun-if-changed=../../LeanTee/Guest.lean");
    println!("cargo:rerun-if-changed=../../LeanTee/Hash.lean");
    println!("cargo:rerun-if-changed=../../native/sha256_portable.c");
    println!("cargo:rerun-if-changed=../../host/lean_sp1_runtime");
    println!("cargo:rerun-if-changed=../../host/lean_sp1_init_min");

    if std::env::var_os("CC_riscv64im_succinct_zkvm_elf").is_none() {
        let fallback = env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/"))
            .join(".sp1/bin/riscv64-unknown-elf-gcc");
        if fallback.exists() {
            env::set_var("CC_riscv64im_succinct_zkvm_elf", &fallback);
        }
    }

    if !guest_a.exists() || env::var_os("SP1_LEAN_FORCE_GUEST_BUILD").is_some() {
        let status = Command::new("bash")
            .arg(root.join("scripts/sp1_lean_guest_build.sh"))
            .current_dir(&root)
            .status()
            .expect("failed to run sp1_lean_guest_build.sh");
        assert!(status.success(), "sp1_lean_guest_build.sh failed");
    }

    assert!(
        guest_a.exists(),
        "missing {} — run scripts/sp1_lean_guest_build.sh",
        guest_a.display()
    );
    assert!(
        lean_a.exists(),
        "missing {} — run scripts/sp1_lean_runtime_build.sh",
        lean_a.display()
    );

    println!("cargo:rustc-link-search=native={}", cache.display());
    println!("cargo:rustc-link-search=native={}", runtime.display());
    // SP1 RISC-V newlib / libstdc++ / libgcc
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"));
    let sysroot = home.join(".sp1/riscv/riscv64-unknown-elf/lib");
    if sysroot.exists() {
        println!("cargo:rustc-link-search=native={}", sysroot.display());
    }
    let libgcc = home.join(".sp1/riscv/lib/gcc/riscv64-unknown-elf/15.2.0");
    if libgcc.exists() {
        println!("cargo:rustc-link-search=native={}", libgcc.display());
    } else if let Ok(out) = Command::new(
        env::var_os("CC_riscv64im_succinct_zkvm_elf")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".sp1/bin/riscv64-unknown-elf-gcc")),
    )
    .arg("-print-libgcc-file-name")
    .output()
    {
        if let Some(parent) = PathBuf::from(String::from_utf8_lossy(&out.stdout).trim())
            .parent()
        {
            println!("cargo:rustc-link-search=native={}", parent.display());
        }
    }

    println!("cargo:rustc-link-lib=static=LeanTeeGuest");
    println!("cargo:rustc-link-lib=static=Lean");
    // SP1 provides libm; pull newlib libc for libstdc++ locale/wchar deps.
    println!("cargo:rustc-link-lib=static=stdc++");
    println!("cargo:rustc-link-lib=static=c");
    println!("cargo:rustc-link-lib=static=gcc");
    println!("cargo:rustc-link-arg=--allow-multiple-definition");
}
