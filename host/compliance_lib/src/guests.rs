//! First-party guest registry (mirrors config/guests/registry.json + LeanTee.Guests).

use lean_tee_receipt::{
    action_allowed_with, concat_len_prefixed, hash_suite, parse_allow_prefixes, CryptoSuite,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GuestDesc {
    pub guest_id: &'static str,
    pub code_id: &'static [u8],
    pub actions: &'static [&'static str],
}

pub const COMPLIANCE: GuestDesc = GuestDesc {
    guest_id: "compliance_operator",
    code_id: b"lean-tee/compliance_operator/v1",
    actions: &[
        "vote.yes",
        "vote.no",
        "supplier.register",
        "purchaser.approve",
        "purchaser.reject",
        "trade.submit",
    ],
};

pub const VOTING: GuestDesc = GuestDesc {
    guest_id: "voting_operator",
    code_id: b"lean-tee/voting_operator/v1",
    actions: &["vote.yes", "vote.no"],
};

pub const ONBOARDING: GuestDesc = GuestDesc {
    guest_id: "onboarding_operator",
    code_id: b"lean-tee/onboarding_operator/v1",
    actions: &["supplier.register", "purchaser.approve", "purchaser.reject"],
};

pub const TRADE: GuestDesc = GuestDesc {
    guest_id: "trade_operator",
    code_id: b"lean-tee/trade_operator/v1",
    actions: &["trade.submit"],
};

pub const BUILTIN: &[GuestDesc] = &[COMPLIANCE, VOTING, ONBOARDING, TRADE];

pub fn normalize_guest_id(id: &str) -> &str {
    let t = id.trim();
    if t.is_empty() || t == "compliance_operator/v1" {
        "compliance_operator"
    } else {
        t
    }
}

pub fn resolve_guest(id: &str) -> Result<&'static GuestDesc, String> {
    let id = normalize_guest_id(id);
    BUILTIN
        .iter()
        .find(|g| g.guest_id == id)
        .ok_or_else(|| format!("unknown guest_id={id}"))
}

pub fn resolve_guest_by_code_hash(code: &[u8], suite: CryptoSuite) -> Option<&'static GuestDesc> {
    BUILTIN
        .iter()
        .find(|g| code_hash_for(g, suite).as_slice() == code)
}

pub fn code_hash_for(g: &GuestDesc, suite: CryptoSuite) -> [u8; 32] {
    hash_suite(suite, g.code_id)
}

pub fn allow_prefixes(g: &GuestDesc) -> Vec<String> {
    g.actions.iter().map(|a| format!("action={a}")).collect()
}

pub fn effective_prefixes(g: &GuestDesc, rules_raw: Option<&[u8]>) -> Vec<String> {
    let builtin = allow_prefixes(g);
    if let Some(raw) = rules_raw {
        if let Ok(t) = std::str::from_utf8(raw) {
            if let Some(asked) = parse_allow_prefixes(t) {
                let filtered: Vec<String> = asked
                    .into_iter()
                    .filter(|p| builtin.iter().any(|b| b == p))
                    .collect();
                if !filtered.is_empty() {
                    return filtered;
                }
            }
        }
    }
    builtin
}

pub fn run_guest(
    g: &GuestDesc,
    rules_hash: &[u8],
    inputs: &[u8],
    rules_raw: Option<&[u8]>,
    suite: CryptoSuite,
) -> Vec<u8> {
    let text = std::str::from_utf8(inputs).unwrap_or("");
    let prefixes = effective_prefixes(g, rules_raw);
    let pref_refs: Vec<&str> = prefixes.iter().map(|s| s.as_str()).collect();
    let allowed = action_allowed_with(&pref_refs, text);
    let decision = if allowed { "allow" } else { "deny" };
    let reason = hash_suite(suite, &concat_len_prefixed(&[rules_hash, inputs]));
    format!("decision={decision}\nreason={}\n", hex::encode(reason)).into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use lean_tee_receipt::{sha256, SUITE_SHA256_MOCK};

    #[test]
    fn resolve_defaults() {
        assert_eq!(resolve_guest("").unwrap().guest_id, "compliance_operator");
        assert_eq!(resolve_guest("voting_operator").unwrap().actions.len(), 2);
        assert!(resolve_guest("nope").is_err());
    }

    #[test]
    fn voting_denies_trade() {
        let g = resolve_guest("voting_operator").unwrap();
        let rules = b"allow=vote.yes,vote.no\n";
        let rh = sha256(rules);
        let out = run_guest(
            g,
            &rh,
            b"action=trade.submit\n",
            Some(rules),
            CryptoSuite::Sha256Mock,
        );
        assert!(String::from_utf8(out).unwrap().starts_with("decision=deny\n"));
        let _ = SUITE_SHA256_MOCK;
    }

    #[test]
    fn distinct_code_hashes() {
        let s = CryptoSuite::Sha256Mock;
        let mut set = std::collections::HashSet::new();
        for g in BUILTIN {
            assert!(set.insert(code_hash_for(g, s)));
        }
    }
}
