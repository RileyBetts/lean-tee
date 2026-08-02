//! Shared lean-tee receipt cryptography (matches `LeanTee.Hash` / `Guest.mockProof`).
//!
//! Profile **lean-tee-v1**: mock proof domain `lean-tee/mock-proof/v1`.
//! Consumers (Anchor Strict, prove_server, Python) should depend on this crate
//! instead of reimplementing length-prefixed SHA-256.

use sha2::{Digest, Sha256};

pub const CODE_ID: &[u8] = b"lean-tee/compliance_operator/v1";
pub const RESULT_DOMAIN: &[u8] = b"lean-tee/v1";
pub const MOCK_PROOF_DOMAIN: &[u8] = b"lean-tee/mock-proof/v1";
pub const PROFILE_V1: &str = "lean-tee-v1";
pub const PROFILE_V2: &str = "lean-tee-v2";

/// Default action prefixes when rules/inputs omit `allow=`.
pub const DEFAULT_ALLOW_PREFIXES: &[&str] = &[
    "action=vote.yes",
    "action=vote.no",
    "action=supplier.register",
    "action=purchaser.approve",
    "action=purchaser.reject",
    "action=trade.submit",
];

pub fn sha256(data: &[u8]) -> [u8; 32] {
    Sha256::digest(data).into()
}

pub fn code_hash() -> [u8; 32] {
    sha256(CODE_ID)
}

/// Length-prefixed concatenation matching `LeanTee.Hash.concatLenPrefixed`.
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
    sha256(&concat_len_prefixed(&[
        RESULT_DOMAIN,
        code,
        config,
        inputs,
        outputs,
        nonce,
    ]))
}

pub fn mock_proof(
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
) -> [u8; 32] {
    sha256(&concat_len_prefixed(&[
        MOCK_PROOF_DOMAIN,
        code,
        config,
        inputs,
        outputs,
    ]))
}

pub fn verify_mock_proof(
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    proof: &[u8],
) -> bool {
    proof == mock_proof(code, config, inputs, outputs)
}

pub fn verify_result_hash(
    code: &[u8],
    config: &[u8],
    inputs: &[u8],
    outputs: &[u8],
    nonce: &[u8],
    evidence: &[u8],
) -> bool {
    evidence == result_hash(code, config, inputs, outputs, nonce)
}

/// Canonical interaction binding for Anchor / multi-party ledgers.
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

/// Parse `allow=a,b,c` from rules or inputs UTF-8 (first matching line).
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

/// Resolve allow-list: rules bytes → inputs → defaults.
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

    #[test]
    fn code_hash_stable() {
        assert_eq!(code_hash().len(), 32);
        assert_eq!(
            hex_encode(&code_hash()),
            hex_encode(&sha256(CODE_ID))
        );
    }

    #[test]
    fn bind_and_allow_parse() {
        let inputs = bind_interaction("vote.yes", "ballot-1", "");
        let t = std::str::from_utf8(&inputs).unwrap();
        assert!(t.starts_with("action=vote.yes\n"));
        assert!(t.contains("interaction=ballot-1\n"));
        let rules = b"allow=vote.yes,vote.no\n";
        let prefs = resolve_allow_prefixes(Some(rules), &inputs);
        assert!(action_allowed_with(
            &prefs.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
            t
        ));
    }

    #[test]
    fn golden_vectors_match_committed() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../testdata/golden_v1.json");
        let raw = fs::read_to_string(&root).expect("testdata/golden_v1.json");
        let v: serde_json::Value = serde_json::from_str(&raw).unwrap();
        let code = hex_decode(v["code_hash_hex"].as_str().unwrap()).unwrap();
        let config = hex_decode(v["config_hash_hex"].as_str().unwrap()).unwrap();
        let inputs = hex_decode(v["inputs_hex"].as_str().unwrap()).unwrap();
        let outputs = hex_decode(v["outputs_hex"].as_str().unwrap()).unwrap();
        let nonce = hex_decode(v["nonce_hex"].as_str().unwrap()).unwrap();
        let evidence = hex_decode(v["evidence_root_hex"].as_str().unwrap()).unwrap();
        let proof = hex_decode(v["proof_ref_hex"].as_str().unwrap()).unwrap();
        assert_eq!(result_hash(&code, &config, &inputs, &outputs, &nonce).as_slice(), evidence);
        assert_eq!(mock_proof(&code, &config, &inputs, &outputs).as_slice(), proof);
        assert_eq!(code.as_slice(), code_hash().as_slice());
    }
}
