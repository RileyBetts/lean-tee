//! Lean-specified GuestProg interpreter (mirrors `LeanTee.GuestProg`).
//! Executed natively and inside the SP1 RISC-V `guest_prog_runtime`.

use lean_tee_receipt::{concat_len_prefixed, hash_suite, hex_encode, sha256, CryptoSuite};

pub const RUNTIME_CODE_ID: &[u8] = b"lean-tee/guest_prog_runtime/lean-sp1/v1";
pub const RUNTIME_GUEST_ID: &str = "guest_prog_runtime";
pub const PROG_VERSION_V1: &str = "lean-tee-guest-prog/v1";
pub const PROG_VERSION_V2: &str = "lean-tee-guest-prog/v2";
pub const DEFAULT_MAX_PROGRAM_BYTES: usize = 65536;
pub const DEFAULT_MAX_INPUT_BYTES: usize = 65536;

pub fn runtime_code_hash(suite: CryptoSuite) -> [u8; 32] {
    hash_suite(suite, RUNTIME_CODE_ID)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Program {
    pub name: String,
    pub allow: Vec<String>,
    pub deny: Vec<String>,
    pub require_interaction: bool,
    pub max_input_bytes: Option<usize>,
}

impl Program {
    pub fn wire_version(&self) -> &'static str {
        if self.deny.is_empty() && !self.require_interaction && self.max_input_bytes.is_none() {
            PROG_VERSION_V1
        } else {
            PROG_VERSION_V2
        }
    }

    pub fn serialize(&self) -> Vec<u8> {
        let mut lines = vec![self.wire_version().to_string()];
        if !self.name.is_empty() {
            lines.push(format!("name={}", self.name));
        }
        lines.push(format!("allow={}", self.allow.join(",")));
        if !self.deny.is_empty() {
            lines.push(format!("deny={}", self.deny.join(",")));
        }
        if self.require_interaction {
            lines.push("require_interaction=true".to_string());
        }
        if let Some(n) = self.max_input_bytes {
            lines.push(format!("max_input_bytes={n}"));
        }
        format!("{}\n", lines.join("\n")).into_bytes()
    }

    pub fn hash(&self) -> [u8; 32] {
        sha256(&self.serialize())
    }

    pub fn allow_prefixes(&self) -> Vec<String> {
        self.allow.iter().map(|a| format!("action={a}")).collect()
    }

    pub fn deny_prefixes(&self) -> Vec<String> {
        self.deny.iter().map(|a| format!("action={a}")).collect()
    }

    pub fn effective_max_input(&self) -> usize {
        self.max_input_bytes.unwrap_or(DEFAULT_MAX_INPUT_BYTES)
    }
}

fn parse_bool(s: &str) -> Result<bool, String> {
    match s.trim() {
        "true" | "1" | "yes" => Ok(true),
        "false" | "0" | "no" => Ok(false),
        other => Err(format!("guest prog: bad bool={other}")),
    }
}

fn has_interaction_line(text: &str) -> bool {
    text.lines()
        .map(str::trim)
        .any(|l| l.starts_with("interaction="))
}

pub fn parse(program: &[u8]) -> Result<Program, String> {
    parse_with_limit(program, DEFAULT_MAX_PROGRAM_BYTES)
}

pub fn parse_with_limit(program: &[u8], max_program_bytes: usize) -> Result<Program, String> {
    if program.len() > max_program_bytes {
        return Err(format!(
            "guest prog: program exceeds max_program_bytes={max_program_bytes}"
        ));
    }
    let text = std::str::from_utf8(program).map_err(|_| "guest prog: not utf-8".to_string())?;
    let lines: Vec<&str> = text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect();
    let (ver, rest) = lines
        .split_first()
        .ok_or_else(|| "guest prog: empty".to_string())?;
    if *ver != PROG_VERSION_V1 && *ver != PROG_VERSION_V2 {
        return Err(format!("guest prog: unsupported version={ver}"));
    }
    let mut name = String::new();
    let mut allow: Vec<String> = Vec::new();
    let mut deny: Vec<String> = Vec::new();
    let mut require_interaction = false;
    let mut max_input_bytes: Option<usize> = None;
    for line in rest {
        if let Some(n) = line.strip_prefix("name=") {
            name = n.to_string();
        } else if let Some(a) = line.strip_prefix("allow=") {
            allow = a
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
        } else if let Some(d) = line.strip_prefix("deny=") {
            deny = d
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
        } else if let Some(v) = line.strip_prefix("require_interaction=") {
            require_interaction = parse_bool(v)?;
        } else if let Some(v) = line.strip_prefix("max_input_bytes=") {
            max_input_bytes = Some(
                v.trim()
                    .parse()
                    .map_err(|_| format!("guest prog: bad max_input_bytes={v}"))?,
            );
        } else if line.starts_with('#') {
            continue;
        } else {
            return Err(format!("guest prog: bad line={line}"));
        }
    }
    if allow.is_empty() {
        return Err("guest prog: empty allow=".into());
    }
    if *ver == PROG_VERSION_V1
        && (!deny.is_empty() || require_interaction || max_input_bytes.is_some())
    {
        return Err(
            "guest prog: v1 cannot use deny/require_interaction/max_input_bytes".into(),
        );
    }
    Ok(Program {
        name,
        allow,
        deny,
        require_interaction,
        max_input_bytes,
    })
}

pub fn run(program: &Program, inputs: &[u8]) -> Vec<u8> {
    let text = std::str::from_utf8(inputs).unwrap_or("");
    let decision = if inputs.len() > program.effective_max_input() {
        "deny"
    } else if program.require_interaction && !has_interaction_line(text) {
        "deny"
    } else if program.deny_prefixes().iter().any(|p| text.starts_with(p)) {
        "deny"
    } else if program.allow_prefixes().iter().any(|p| text.starts_with(p)) {
        "allow"
    } else {
        "deny"
    };
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
    fn roundtrip_v1_and_run() {
        let p = Program {
            name: "demo".into(),
            allow: vec!["vote.yes".into(), "vote.no".into()],
            deny: vec![],
            require_interaction: false,
            max_input_bytes: None,
        };
        let raw = p.serialize();
        assert!(std::str::from_utf8(&raw).unwrap().starts_with(PROG_VERSION_V1));
        let q = parse(&raw).unwrap();
        assert_eq!(p, q);
        let out = run(&q, b"action=vote.yes\n");
        assert!(String::from_utf8(out).unwrap().starts_with("decision=allow\n"));
        let deny = run(&q, b"action=trade.submit\n");
        assert!(String::from_utf8(deny).unwrap().starts_with("decision=deny\n"));
    }

    #[test]
    fn v2_deny_interaction_and_limits() {
        let p = Program {
            name: "demo".into(),
            allow: vec!["vote.yes".into()],
            deny: vec!["vote.yes".into()], // deny wins
            require_interaction: true,
            max_input_bytes: Some(64),
        };
        let raw = p.serialize();
        assert!(std::str::from_utf8(&raw).unwrap().starts_with(PROG_VERSION_V2));
        let q = parse(&raw).unwrap();
        assert_eq!(p, q);
        // missing interaction
        let d = run(&q, b"action=vote.yes\n");
        assert!(String::from_utf8(d).unwrap().starts_with("decision=deny\n"));
        // deny wins even with interaction
        let d2 = run(&q, b"action=vote.yes\ninteraction=x\n");
        assert!(String::from_utf8(d2).unwrap().starts_with("decision=deny\n"));

        let p2 = Program {
            name: String::new(),
            allow: vec!["vote.yes".into()],
            deny: vec![],
            require_interaction: true,
            max_input_bytes: Some(64),
        };
        let ok = run(&p2, b"action=vote.yes\ninteraction=cli\n");
        assert!(String::from_utf8(ok).unwrap().starts_with("decision=allow\n"));
        let big = vec![b'a'; 100];
        let oversized = run(&p2, &big);
        assert!(String::from_utf8(oversized)
            .unwrap()
            .starts_with("decision=deny\n"));
    }

    #[test]
    fn program_size_limit() {
        let mut huge = b"lean-tee-guest-prog/v1\nallow=a\n".to_vec();
        huge.extend(std::iter::repeat(b'x').take(100));
        assert!(parse_with_limit(&huge, 20).is_err());
    }
}
