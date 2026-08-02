//! Compliance operator path shared by native host and SP1 RISC-V guest.
//! Must stay behaviorally aligned with `LeanTee.Guest.runCompliance`.

use sha2::{Digest, Sha256};

pub const CODE_ID: &[u8] = b"lean-tee/compliance_operator/v1";

/// SHA-256 of the guest identity string (Lean `demoCodeHash`).
pub fn code_hash() -> [u8; 32] {
    Sha256::digest(CODE_ID).into()
}

pub fn sha256(data: &[u8]) -> [u8; 32] {
    Sha256::digest(data).into()
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

/// Allowed action prefixes (must match `LeanTee.Guest.actionAllowed`).
pub fn action_allowed(text: &str) -> bool {
    text.starts_with("action=vote.yes")
        || text.starts_with("action=vote.no")
        || text.starts_with("action=supplier.register")
        || text.starts_with("action=purchaser.approve")
        || text.starts_with("action=purchaser.reject")
        || text.starts_with("action=trade.submit")
}

/// Single measured path: interface framing + compliance main.
pub fn run_compliance(rules_hash: &[u8], inputs: &[u8]) -> Vec<u8> {
    let text = std::str::from_utf8(inputs).unwrap_or("");
    let allowed = action_allowed(text);
    let decision = if allowed { "allow" } else { "deny" };
    let reason = sha256(&concat_len_prefixed(&[rules_hash, inputs]));
    format!("decision={decision}\nreason={}\n", hex::encode(reason)).into_bytes()
}

/// Dev mock proof (same as Lean `Guest.mockProof`) used when SP1 prove is unavailable.
pub fn mock_proof(code_hash: &[u8], config_hash: &[u8], inputs: &[u8], outputs: &[u8]) -> [u8; 32] {
    sha256(&concat_len_prefixed(&[
        b"lean-tee/mock-proof/v1",
        code_hash,
        config_hash,
        inputs,
        outputs,
    ]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allow_vote_yes() {
        let rules = sha256(b"rules=vote.yes,vote.no");
        let out = run_compliance(&rules, b"action=vote.yes\n");
        let s = String::from_utf8(out).unwrap();
        assert!(s.starts_with("decision=allow\n"));
    }

    #[test]
    fn deny_transfer() {
        let rules = sha256(b"rules=vote.yes,vote.no");
        let out = run_compliance(&rules, b"action=transfer.funds\n");
        assert!(String::from_utf8(out).unwrap().starts_with("decision=deny\n"));
    }

    #[test]
    fn allow_trade_and_onboarding() {
        let rules = sha256(b"rules=strict-v1");
        for action in [
            b"action=supplier.register\n".as_slice(),
            b"action=purchaser.approve\n",
            b"action=trade.submit\n",
        ] {
            let out = run_compliance(&rules, action);
            assert!(
                String::from_utf8(out).unwrap().starts_with("decision=allow\n"),
                "expected allow for {:?}",
                std::str::from_utf8(action)
            );
        }
    }
}
