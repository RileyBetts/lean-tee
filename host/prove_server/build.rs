fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Build the RISC-V guest ELF via SP1 toolchain (`cargo prove` / succinct rustc).
    sp1_build::build_program("../guest");

    let protoc = protoc_bin_vendored::protoc_bin_path()?;
    std::env::set_var("PROTOC", &protoc);
    let proto = "../../proto/lean_tee/v1/tee.proto";
    println!("cargo:rerun-if-changed={proto}");
    println!("cargo:rerun-if-changed=../guest");
    tonic_build::configure()
        .build_client(false)
        .build_server(true)
        .compile_protos(&[proto], &["../../proto"])?;
    Ok(())
}
