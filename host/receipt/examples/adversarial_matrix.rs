// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

use lean_tee_receipt::*;

fn expect_err(suite: &str, label: &str, code: &[u8], config: &[u8], inputs: &[u8], outputs: &[u8], nonce: &[u8], evidence: &[u8], proof: &[u8], want: &str) {
    let err = accept_mock_receipt(suite, code, config, inputs, outputs, nonce, evidence, proof)
        .expect_err(label);
    assert!(
        err.contains(want),
        "{label}: want `{want}` in `{err}`"
    );
}

fn main() {
    let suite = CryptoSuite::Sha256Mock;
    let rules = b"allow=vote.yes,vote.no\n";
    let code = code_hash_suite(suite);
    let config = hash_suite(suite, rules);
    let inputs = bind_interaction("vote.yes", "adv-rs-1", "");
    let reason = hash_suite(suite, &concat_len_prefixed(&[&config[..], &inputs[..]]));
    let outputs = format!("decision=allow\nreason={}\n", hex_encode(&reason)).into_bytes();
    let nonce = hash_suite(suite, &concat_len_prefixed(&[&inputs[..], &config[..]]));
    let evidence = result_hash_suite(suite, &code, &config, &inputs, &outputs, &nonce);
    let proof = mock_proof_suite(suite, &code, &config, &inputs, &outputs).unwrap();

    accept_mock_receipt(suite.id(), &code, &config, &inputs, &outputs, &nonce, &evidence, &proof)
        .expect("honest");
    accept_mock_receipt("", &code, &config, &inputs, &outputs, &nonce, &evidence, &proof)
        .expect("empty suite");

    let forged_out = b"decision=allow\nforged\n".as_slice();
    expect_err(
        suite.id(),
        "outputs",
        &code,
        &config,
        &inputs,
        forged_out,
        &nonce,
        &evidence,
        &proof,
        "resultHash",
    );
    expect_err(
        suite.id(),
        "inputs",
        &code,
        &config,
        b"action=vote.no\n",
        &outputs,
        &nonce,
        &evidence,
        &proof,
        "resultHash",
    );
    expect_err(
        suite.id(),
        "nonce",
        &code,
        &config,
        &inputs,
        &outputs,
        b"bad-nonce",
        &evidence,
        &proof,
        "resultHash",
    );
    expect_err(
        suite.id(),
        "evidence",
        &code,
        &config,
        &inputs,
        &outputs,
        &nonce,
        &hash_suite(suite, b"wrong-evidence"),
        &proof,
        "resultHash",
    );
    expect_err(
        suite.id(),
        "proof",
        &code,
        &config,
        &inputs,
        &outputs,
        &nonce,
        &evidence,
        &hash_suite(suite, b"wrong-proof"),
        "mock proof",
    );
    expect_err(
        SUITE_BLAKE3_MOCK,
        "suite confusion",
        &code,
        &config,
        &inputs,
        &outputs,
        &nonce,
        &evidence,
        &proof,
        "resultHash",
    );
    expect_err(
        "nope",
        "unknown suite",
        &code,
        &config,
        &inputs,
        &outputs,
        &nonce,
        &evidence,
        &proof,
        "unknown",
    );

    // Honest blake3 must accept under its own suite
    let b3 = CryptoSuite::Blake3Mock;
    let code3 = code_hash_suite(b3);
    let config3 = hash_suite(b3, rules);
    let inputs3 = bind_interaction("vote.yes", "adv-b3", "");
    let reason3 = hash_suite(b3, &concat_len_prefixed(&[&config3[..], &inputs3[..]]));
    let outputs3 = format!("decision=allow\nreason={}\n", hex_encode(&reason3)).into_bytes();
    let nonce3 = hash_suite(b3, &concat_len_prefixed(&[&inputs3[..], &config3[..]]));
    let ev3 = result_hash_suite(b3, &code3, &config3, &inputs3, &outputs3, &nonce3);
    let proof3 = mock_proof_suite(b3, &code3, &config3, &inputs3, &outputs3).unwrap();
    accept_mock_receipt(b3.id(), &code3, &config3, &inputs3, &outputs3, &nonce3, &ev3, &proof3)
        .expect("blake3 honest");

    println!("adversarial_matrix rust OK");
}
