//! Compliance operator — aligned with `LeanTee.Guest`.
//! Receipt crypto lives in `lean_tee_receipt`.

use lean_tee_receipt::{
    action_allowed_with, concat_len_prefixed, resolve_allow_prefixes, sha256,
};

pub use lean_tee_receipt::{
    bind_interaction, code_hash, mock_proof, result_hash, verify_mock_proof, verify_result_hash,
    CODE_ID, DEFAULT_ALLOW_PREFIXES, MOCK_PROOF_DOMAIN, PROFILE_V1, PROFILE_V2, RESULT_DOMAIN,
};

/// Run compliance. `rules_raw` is optional raw rules (for `allow=`); `rules_hash` is
/// always the measurement config digest used in the reason line.
pub fn run_compliance(rules_hash: &[u8], inputs: &[u8]) -> Vec<u8> {
    run_compliance_with_rules(rules_hash, inputs, None)
}

pub fn run_compliance_with_rules(
    rules_hash: &[u8],
    inputs: &[u8],
    rules_raw: Option<&[u8]>,
) -> Vec<u8> {
    let text = std::str::from_utf8(inputs).unwrap_or("");
    let prefixes = resolve_allow_prefixes(rules_raw, inputs);
    let pref_refs: Vec<&str> = prefixes.iter().map(|s| s.as_str()).collect();
    let allowed = action_allowed_with(&pref_refs, text);
    let decision = if allowed { "allow" } else { "deny" };
    let reason = sha256(&concat_len_prefixed(&[rules_hash, inputs]));
    format!("decision={decision}\nreason={}\n", hex::encode(reason)).into_bytes()
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
}
