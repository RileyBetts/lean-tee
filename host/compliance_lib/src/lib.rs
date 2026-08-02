//! Multi-guest compliance operators — aligned with `LeanTee.Guests`.
//! Receipt crypto lives in `lean_tee_receipt`.

mod guests;

pub use guests::*;

use lean_tee_receipt::CryptoSuite;

pub use lean_tee_receipt::{
    accept_mock_receipt, bind_interaction, code_hash, code_hash_suite, mock_proof, mock_proof_suite,
    result_hash, result_hash_suite, verify_mock_proof, verify_result_hash, CODE_ID,
    DEFAULT_ALLOW_PREFIXES, MOCK_PROOF_DOMAIN, PROFILE_V1, PROFILE_V2, RESULT_DOMAIN,
    SUITE_BLAKE3_MOCK, SUITE_SHA256_MOCK, SUITE_SHA256_SP1,
};

/// Back-compat: compliance_operator with optional allow= rules.
pub fn run_compliance(rules_hash: &[u8], inputs: &[u8]) -> Vec<u8> {
    run_compliance_with_rules(rules_hash, inputs, None)
}

pub fn run_compliance_with_rules(
    rules_hash: &[u8],
    inputs: &[u8],
    rules_raw: Option<&[u8]>,
) -> Vec<u8> {
    run_guest(
        &COMPLIANCE,
        rules_hash,
        inputs,
        rules_raw,
        CryptoSuite::Sha256Mock,
    )
}

pub fn run_guest_id(
    guest_id: &str,
    rules_hash: &[u8],
    inputs: &[u8],
    rules_raw: Option<&[u8]>,
) -> Result<Vec<u8>, String> {
    let g = resolve_guest(guest_id)?;
    Ok(run_guest(
        g,
        rules_hash,
        inputs,
        rules_raw,
        CryptoSuite::Sha256Mock,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use lean_tee_receipt::sha256;

    #[test]
    fn allow_vote_yes() {
        let rules = b"allow=vote.yes,vote.no\n";
        let rh = sha256(rules);
        let out = run_compliance_with_rules(&rh, b"action=vote.yes\n", Some(rules));
        assert!(String::from_utf8(out).unwrap().starts_with("decision=allow\n"));
    }

    #[test]
    fn deny_transfer() {
        let rules = b"allow=vote.yes,vote.no\n";
        let rh = sha256(rules);
        let out = run_compliance_with_rules(&rh, b"action=transfer.funds\n", Some(rules));
        assert!(String::from_utf8(out).unwrap().starts_with("decision=deny\n"));
    }

    #[test]
    fn custom_allow_only_trade() {
        let rules = b"allow=trade.submit\n";
        let rh = sha256(rules);
        let deny = run_compliance_with_rules(&rh, b"action=vote.yes\n", Some(rules));
        assert!(String::from_utf8(deny).unwrap().starts_with("decision=deny\n"));
        let allow = run_compliance_with_rules(&rh, b"action=trade.submit\n", Some(rules));
        assert!(String::from_utf8(allow).unwrap().starts_with("decision=allow\n"));
    }

    #[test]
    fn per_guest_surfaces() {
        let rh = sha256(b"rules");
        let v = run_guest_id("voting_operator", &rh, b"action=vote.yes\n", None).unwrap();
        assert!(String::from_utf8(v).unwrap().starts_with("decision=allow\n"));
        let t = run_guest_id("trade_operator", &rh, b"action=vote.yes\n", None).unwrap();
        assert!(String::from_utf8(t).unwrap().starts_with("decision=deny\n"));
    }
}
