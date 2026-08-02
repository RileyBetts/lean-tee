use lean_tee_receipt::*;

fn main() {
    let suite = CryptoSuite::Blake3Mock;
    let rules = b"allow=vote.yes,vote.no\n";
    let code = code_hash_suite(suite);
    let config = hash_suite(suite, rules);
    let inputs = bind_interaction("vote.yes", "golden-blake3-1", "");
    let reason = hash_suite(suite, &concat_len_prefixed(&[&config[..], &inputs[..]]));
    let outputs = format!("decision=allow\nreason={}\n", hex_encode(&reason)).into_bytes();
    let nonce = hash_suite(suite, &concat_len_prefixed(&[&inputs[..], &config[..]]));
    let evidence = result_hash_suite(suite, &code, &config, &inputs, &outputs, &nonce);
    let proof = mock_proof_suite(suite, &code, &config, &inputs, &outputs).unwrap();
    print!("{{\n");
    print!("  \"crypto_suite\": \"{}\",\n", suite.id());
    print!("  \"code_hash_hex\": \"{}\",\n", hex_encode(&code));
    print!("  \"config_hash_hex\": \"{}\",\n", hex_encode(&config));
    print!("  \"inputs_hex\": \"{}\",\n", hex_encode(&inputs));
    print!("  \"outputs_hex\": \"{}\",\n", hex_encode(&outputs));
    print!("  \"nonce_hex\": \"{}\",\n", hex_encode(&nonce));
    print!("  \"evidence_root_hex\": \"{}\",\n", hex_encode(&evidence));
    print!("  \"proof_ref_hex\": \"{}\",\n", hex_encode(&proof));
    print!("  \"rules_utf8\": \"allow=vote.yes,vote.no\\n\"\n");
    print!("}}\n");
}
