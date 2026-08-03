fn main() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(feature = "sp1")]
    {
        sp1_build::build_program("../guest");
        println!("cargo:rerun-if-changed=../guest");
        sp1_build::build_program("../guest_lean_spike");
        println!("cargo:rerun-if-changed=../guest_lean_spike");
        println!("cargo:rerun-if-changed=../guest_lean_spike/c");
        sp1_build::build_program("../guest_lean");
        println!("cargo:rerun-if-changed=../guest_lean");
        println!("cargo:rerun-if-changed=../lean_sp1_runtime");
        println!("cargo:rerun-if-changed=../lean_sp1_init_min");
    }

    let protoc = protoc_bin_vendored::protoc_bin_path()?;
    std::env::set_var("PROTOC", &protoc);
    let proto = "../../proto/lean_tee/v1/tee.proto";
    println!("cargo:rerun-if-changed={proto}");
    tonic_build::configure()
        .build_client(false)
        .build_server(true)
        .compile_protos(&[proto], &["../../proto"])?;
    Ok(())
}
