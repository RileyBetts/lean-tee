// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Shared lean-tee receipt cryptography with registered CryptoSuites.
//! See `docs/CRYPTO.md`.

use blake3::Hasher as Blake3;
use sha2::{Digest, Sha256};

pub const CODE_ID: &[u8] = b"lean-tee/compliance_operator/lean-sp1/v1";

pub const SUITE_SHA256_MOCK: &str = "sha256+mock";
pub const SUITE_SHA256_SP1: &str = "sha256+sp1";
pub const SUITE_BLAKE3_MOCK: &str = "blake3+mock";

pub const PROFILE_V1: &str = "lean-tee-v1";
pub const PROFILE_V2: &str = "lean-tee-v2";

pub const RESULT_DOMAIN_SHA256: &[u8] = b"lean-tee/v1";
pub const MOCK_PROOF_DOMAIN_SHA256: &[u8] = b"lean-tee/mock-proof/v1";
pub const RESULT_DOMAIN_BLAKE3: &[u8] = b"lean-tee/blake3/v1";
pub const MOCK_PROOF_DOMAIN_BLAKE3: &[u8] = b"lean-tee/mock-proof-blake3/v1";

/// Back-compat aliases.
pub const RESULT_DOMAIN: &[u8] = RESULT_DOMAIN_SHA256;
pub const MOCK_PROOF_DOMAIN: &[u8] = MOCK_PROOF_DOMAIN_SHA256;

pub const DEFAULT_ALLOW_PREFIXES: &[&str] = &[
    "action=vote.yes",
    "action=vote.no",
    "action=supplier.register",
    "action=purchaser.approve",
    "action=purchaser.reject",
    "action=trade.submit",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CryptoSuite {
    Sha256Mock,
    Sha256Sp1,
    Blake3Mock,
}

impl CryptoSuite {
    pub fn parse(s: &str) -> Result<Self, String> {
        let n = normalize_suite(s);
        match n.as_str() {
            SUITE_SHA256_MOCK => Ok(Self::Sha256Mock),
            SUITE_SHA256_SP1 => Ok(Self::Sha256Sp1),
            SUITE_BLAKE3_MOCK => Ok(Self::Blake3Mock),
            other => Err(format!("unknown crypto_suite={other}")),
        }
    }

    pub fn id(self) -> &'static str {
        match self {
            Self::Sha256Mock => SUITE_SHA256_MOCK,
            Self::Sha256Sp1 => SUITE_SHA256_SP1,
            Self::Blake3Mock => SUITE_BLAKE3_MOCK,
        }
    }

    pub fn result_domain(self) -> &'static [u8] {
        match self {
            Self::Sha256Mock | Self::Sha256Sp1 => RESULT_DOMAIN_SHA256,
            Self::Blake3Mock => RESULT_DOMAIN_BLAKE3,
        }
    }

    pub fn mock_domain(self) -> Option<&'static [u8]> {
        match self {
            Self::Sha256Mock => Some(MOCK_PROOF_DOMAIN_SHA256),
            Self::Blake3Mock => Some(MOCK_PROOF_DOMAIN_BLAKE3),
            Self::Sha256Sp1 => None,
        }
    }

    pub fn is_mock(self) -> bool {
        self.mock_domain().is_some()
    }
}

pub fn normalize_suite(s: &str) -> String {
    let t = s.trim();
    if t.is_empty() || t == PROFILE_V1 {
        SUITE_SHA256_MOCK.to_string()
    } else if t == PROFILE_V2 {
        SUITE_SHA256_SP1.to_string()
    } else {
        t.to_string()
    }
}

pub fn sha256(data: &[u8]) -> [u8; 32] {
    Sha256::digest(data).into()
}

pub fn blake3_hash(data: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    out.copy_from_slice(Blake3::new().update(data).finalize().as_bytes());
    out
}

pub fn hash_suite(suite: CryptoSuite, data: &[u8]) -> [u8; 32] {
    match suite {
        CryptoSuite::Sha256Mock | CryptoSuite::Sha256Sp1 => sha256(data),
        CryptoSuite::Blake3Mock => blake3_hash(data),
    }
}

pub fn code_hash() -> [u8; 32] {
    code_hash_suite(CryptoSuite::Sha256Mock)
}

pub fn code_hash_suite(suite: CryptoSuite) -> [u8; 32] {
    hash_suite(suite, CODE_ID)
}

/// `codeHash` for an arbitrary guest `code_id` string/bytes.
pub fn code_hash_for_id(suite: CryptoSuite, code_id: &[u8]) -> [u8; 32] {
    hash_suite(suite, code_id)
}

pub fn concat_len_prefixed(chunks: &[&[u8]]) -> Vec<u8> {
    let mut out = Vec::new();
    for c in chunks {
        let n = c.len() as u32;
        out.extend_from_slice(&n.to_be_bytes());
        out.extend_from_slice(c);
    }
    out
}

pub fn result_hash(
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    nonce: &[u8],
) -> [u8; 32] {
    result_hash_suite(
        CryptoSuite::Sha256Mock,
        code,
        config,
        inputs,
        outputs,
        nonce,
    )
}

pub fn result_hash_suite(
    suite: CryptoSuite,
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    nonce: &[u8],
) -> [u8; 32] {
    hash_suite(
        suite,
        &concat_len_prefixed(&[
            suite.result_domain(),
            code,
            config,
            inputs,
            outputs,
            nonce,
        ]),
    )
}

pub fn mock_proof(
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
) -> [u8; 32] {
    mock_proof_suite(CryptoSuite::Sha256Mock, code, config, inputs, outputs)
        .expect("sha256+mock has mock domain")
}

pub fn mock_proof_suite(
    suite: CryptoSuite,
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
) -> Result<[u8; 32], String> {
    let domain = suite
        .mock_domain()
        .ok_or_else(|| format!("suite {} has no mock proof", suite.id()))?;
    Ok(hash_suite(
        suite,
        &concat_len_prefixed(&[domain, code, config, inputs, outputs]),
    ))
}

pub fn verify_mock_proof(
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    proof: &[u8],
) -> bool {
    verify_mock_proof_suite(CryptoSuite::Sha256Mock, code, config, inputs, outputs, proof)
        .unwrap_or(false)
}

pub fn verify_mock_proof_suite(
    suite: CryptoSuite,
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    proof: &[u8],
) -> Result<bool, String> {
    let expect = mock_proof_suite(suite, code, config, inputs, outputs)?;
    Ok(proof == expect)
}

pub fn verify_result_hash(
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    nonce: &[u8],
    evidence: &[u8],
) -> bool {
    verify_result_hash_suite(
        CryptoSuite::Sha256Mock,
        code,
        config,
        inputs,
        outputs,
        nonce,
        evidence,
    )
}

pub fn verify_result_hash_suite(
    suite: CryptoSuite,
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    nonce: &[u8],
    evidence: &[u8],
) -> bool {
    evidence == result_hash_suite(suite, code, config, inputs, outputs, nonce)
}

/// Full mock-suite accept: known suite + resultHash + mock proof.
pub fn accept_mock_receipt(
    suite_id: &str,
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    nonce: &[u8],
    evidence: &[u8],
    proof: &[u8],
) -> Result<(), String> {
    let suite = CryptoSuite::parse(suite_id)?;
    if !suite.is_mock() {
        return Err(format!(
            "suite {} is not mock; use host SP1 verify path",
            suite.id()
        ));
    }
    if !verify_result_hash_suite(suite, code, config, inputs, outputs, nonce, evidence) {
        return Err("resultHash mismatch".into());
    }
    if !verify_mock_proof_suite(suite, code, config, inputs, outputs, proof)? {
        return Err("mock proof invalid".into());
    }
    Ok(())
}

pub fn bind_interaction(action: &str, interaction_id: &str, payload: &str) -> Vec<u8> {
    let mut s = format!("action={action}\ninteraction={interaction_id}\n");
    if !payload.is_empty() {
        s.push_str(payload);
        if !payload.ends_with('\n') {
            s.push('\n');
        }
    }
    s.into_bytes()
}

pub fn parse_allow_prefixes(text: &str) -> Option<Vec<String>> {
    for line in text.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("allow=") {
            let list = rest
                .split(',')
                .map(|s| {
                    let t = s.trim();
                    if t.starts_with("action=") {
                        t.to_string()
                    } else {
                        format!("action={t}")
                    }
                })
                .filter(|s| s.len() > "action=".len())
                .collect::<Vec<_>>();
            if !list.is_empty() {
                return Some(list);
            }
        }
    }
    None
}

pub fn action_allowed_with(prefixes: &[&str], inputs_utf8: &str) -> bool {
    prefixes.iter().any(|p| inputs_utf8.starts_with(p))
}

pub fn resolve_allow_prefixes(rules: Option<&[u8]>, inputs: &[u8]) -> Vec<String> {
    if let Some(r) = rules {
        if let Ok(t) = std::str::from_utf8(r) {
            if let Some(p) = parse_allow_prefixes(t) {
                return p;
            }
        }
    }
    if let Ok(t) = std::str::from_utf8(inputs) {
        if let Some(p) = parse_allow_prefixes(t) {
            return p;
        }
    }
    DEFAULT_ALLOW_PREFIXES
        .iter()
        .map(|s| (*s).to_string())
        .collect()
}

pub fn hex_encode(bytes: &[u8]) -> String {
    hex::encode(bytes)
}

pub fn hex_decode(s: &str) -> Result<Vec<u8>, hex::FromHexError> {
    hex::decode(s)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn load_golden(name: &str) -> serde_json::Value {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata").join(name);
        let raw = fs::read_to_string(&root).unwrap_or_else(|e| panic!("missing {name}: {e}"));
        serde_json::from_str(&raw).unwrap()
    }

    fn assert_golden(suite: CryptoSuite, name: &str) {
        let v = load_golden(name);
        assert_eq!(v["crypto_suite"].as_str().unwrap(), suite.id());
        let code = hex_decode(v["code_hash_hex"].as_str().unwrap()).unwrap();
        let config = hex_decode(v["config_hash_hex"].as_str().unwrap()).unwrap();
        let inputs = hex_decode(v["inputs_hex"].as_str().unwrap()).unwrap();
        let outputs = hex_decode(v["outputs_hex"].as_str().unwrap()).unwrap();
        let nonce = hex_decode(v["nonce_hex"].as_str().unwrap()).unwrap();
        let evidence = hex_decode(v["evidence_root_hex"].as_str().unwrap()).unwrap();
        let proof = hex_decode(v["proof_ref_hex"].as_str().unwrap()).unwrap();
        assert_eq!(code.as_slice(), code_hash_suite(suite).as_slice());
        assert_eq!(
            result_hash_suite(suite, &code, &config, &inputs, &outputs, &nonce).as_slice(),
            evidence
        );
        assert_eq!(
            mock_proof_suite(suite, &code, &config, &inputs, &outputs)
                .unwrap()
                .as_slice(),
            proof
        );
        accept_mock_receipt(
            suite.id(),
            &code,
            &config,
            &inputs,
            &outputs,
            &nonce,
            &evidence,
            &proof,
        )
        .unwrap();
    }

    #[test]
    fn normalize_empty_and_profiles() {
        assert_eq!(normalize_suite(""), SUITE_SHA256_MOCK);
        assert_eq!(normalize_suite(PROFILE_V1), SUITE_SHA256_MOCK);
        assert_eq!(normalize_suite(PROFILE_V2), SUITE_SHA256_SP1);
        assert!(CryptoSuite::parse("nope").is_err());
    }

    #[test]
    fn fail_closed_unknown_suite() {
        let err = accept_mock_receipt("nope", &[], &[], &[], &[], &[], &[], &[]).unwrap_err();
        assert!(err.contains("unknown"));
    }

    #[test]
    fn suites_do_not_cross_verify() {
        let code = code_hash_suite(CryptoSuite::Sha256Mock);
        let config = hash_suite(CryptoSuite::Sha256Mock, b"rules");
        let inputs = b"action=vote.yes\n";
        let outputs = b"decision=allow\n";
        let nonce = hash_suite(CryptoSuite::Sha256Mock, b"nonce");
        let ev = result_hash_suite(
            CryptoSuite::Sha256Mock,
            &code,
            &config,
            inputs,
            outputs,
            &nonce,
        );
        let proof = mock_proof_suite(CryptoSuite::Sha256Mock, &code, &config, inputs, outputs).unwrap();
        assert!(accept_mock_receipt(
            SUITE_SHA256_MOCK,
            &code,
            &config,
            inputs,
            outputs,
            &nonce,
            &ev,
            &proof,
        )
        .is_ok());
        assert!(accept_mock_receipt(
            SUITE_BLAKE3_MOCK,
            &code,
            &config,
            inputs,
            outputs,
            &nonce,
            &ev,
            &proof,
        )
        .is_err());
    }

    #[test]
    fn golden_sha256_v1() {
        assert_golden(CryptoSuite::Sha256Mock, "golden_v1.json");
    }

    #[test]
    fn golden_blake3_mock() {
        assert_golden(CryptoSuite::Blake3Mock, "golden_blake3_mock.json");
    }

    #[test]
    fn bind_and_allow_parse() {
        let inputs = bind_interaction("vote.yes", "ballot-1", "");
        let t = std::str::from_utf8(&inputs).unwrap();
        assert!(t.starts_with("action=vote.yes\n"));
        let rules = b"allow=vote.yes,vote.no\n";
        let prefs = resolve_allow_prefixes(Some(rules), &inputs);
        assert!(action_allowed_with(
            &prefs.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
            t
        ));
    }
}
