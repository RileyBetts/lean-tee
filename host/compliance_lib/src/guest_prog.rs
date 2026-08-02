//! Lean-specified GuestProg interpreter (mirrors `LeanTee.GuestProg`).
//! Executed natively and inside the SP1 RISC-V `guest_prog_runtime`.

use lean_tee_receipt::{concat_len_prefixed, hash_suite, hex_encode, sha256, CryptoSuite};

pub const RUNTIME_CODE_ID: &[u8] = b"lean-tee/guest_prog_runtime/v1";
pub const RUNTIME_GUEST_ID: &str = "guest_prog_runtime";
pub const PROG_VERSION: &str = "lean-tee-guest-prog/v1";

pub fn runtime_code_hash(suite: CryptoSuite) -> [u8; 32] {
    hash_suite(suite, RUNTIME_CODE_ID)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Program {
    pub name: String,
    pub allow: Vec<String>,
}

impl Program {
    pub fn serialize(&self) -> Vec<u8> {
        let allow_line = format!("allow={}", self.allow.join(","));
        let body = if self.name.is_empty() {
            format!("{PROG_VERSION}\n{allow_line}\n")
        } else {
            format!("{PROG_VERSION}\nname={}\n{allow_line}\n", self.name)
        };
        body.into_bytes()
    }

    pub fn hash(&self) -> [u8; 32] {
        sha256(&self.serialize())
    }

    pub fn allow_prefixes(&self) -> Vec<String> {
        self.allow.iter().map(|a| format!("action={a}")).collect()
    }
}

pub fn parse(program: &[u8]) -> Result<Program, String> {
    let text = std::str::from_utf8(program).map_err(|_| "guest prog: not utf-8".to_string())?;
    let lines: Vec<&str> = text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect();
    let (ver, rest) = lines
        .split_first()
        .ok_or_else(|| "guest prog: empty".to_string())?;
    if *ver != PROG_VERSION {
        return Err(format!("guest prog: unsupported version={ver}"));
    }
    let mut name = String::new();
    let mut allow: Vec<String> = Vec::new();
    for line in rest {
        if let Some(n) = line.strip_prefix("name=") {
            name = n.to_string();
        } else if let Some(a) = line.strip_prefix("allow=") {
            allow = a
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
        } else if line.starts_with('#') {
            continue;
        } else {
            return Err(format!("guest prog: bad line={line}"));
        }
    }
    if allow.is_empty() {
        return Err("guest prog: empty allow=".into());
    }
    Ok(Program { name, allow })
}

pub fn run(program: &Program, inputs: &[u8]) -> Vec<u8> {
    let text = std::str::from_utf8(inputs).unwrap_or("");
    let allowed = program
        .allow_prefixes()
        .iter()
        .any(|p| text.starts_with(p));
    let decision = if allowed { "allow" } else { "deny" };
    let reason = sha256(&concat_len_prefixed(&[&program.hash()[..], inputs]));
    format!("decision={decision}\nreason={}\n", hex_encode(&reason)).into_bytes()
}

pub fn run_bytes(program: &[u8], inputs: &[u8]) -> Result<Vec<u8>, String> {
    let p = parse(program)?;
    Ok(run(&p, inputs))
}

/// Unified guest entry used by SP1: optional program bytes.
/// Empty program => legacy compliance using `config_hash` as rules hash only
/// (rules body not available in zkVM — use default allow list).
pub fn run_measured(
    config_hash: &[u8; 32],
    inputs: &[u8],
    program: &[u8],
) -> Result<Vec<u8>, String> {
    if program.is_empty() {
        Ok(crate::run_compliance(config_hash, inputs))
    } else {
        let expect = sha256(program);
        if expect != *config_hash {
            return Err("guest prog: config_hash != SHA256(program)".into());
        }
        run_bytes(program, inputs)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_and_run() {
        let p = Program {
            name: "demo".into(),
            allow: vec!["vote.yes".into(), "vote.no".into()],
        };
        let raw = p.serialize();
        let q = parse(&raw).unwrap();
        assert_eq!(p, q);
        let out = run(&q, b"action=vote.yes\n");
        assert!(String::from_utf8(out).unwrap().starts_with("decision=allow\n"));
        let deny = run(&q, b"action=trade.submit\n");
        assert!(String::from_utf8(deny).unwrap().starts_with("decision=deny\n"));
    }
}
