// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Local sealed worker — optional `LEAN_TEE_CONFIDENTIALITY=local`.
//!
//! Hardens against weaker agents (no core dumps, non-dumpable, no secret logs).
//! Does **not** protect against local root / hardware memory inspection.

use lean_tee_compliance::{run_guest_id, run_bytes as guest_prog_run, RUNTIME_GUEST_ID};
use lean_tee_receipt::{hex_encode, sha256};
use std::io::{Read, Write};
use std::process;
use zeroize::{Zeroize, Zeroizing};

fn harden_against_weaker_agents() {
    // Disable core dumps for this process.
    #[cfg(unix)]
    unsafe {
        let lim = libc::rlimit {
            rlim_cur: 0,
            rlim_max: 0,
        };
        let _ = libc::setrlimit(libc::RLIMIT_CORE, &lim);
        // Not dumpable → harder for unprivileged ptrace attach (Yama/ptrace).
        let _ = libc::prctl(libc::PR_SET_DUMPABLE, 0, 0, 0, 0);
    }
    // Optional mlock of current pages (best-effort; ignore failure).
    if std::env::var("LEAN_TEE_SEALED_MLOCK").ok().as_deref() == Some("1") {
        #[cfg(unix)]
        unsafe {
            let _ = libc::mlockall(libc::MCL_CURRENT | libc::MCL_FUTURE);
        }
    }
}

fn read_u32_be(stdin: &mut impl Read) -> Result<u32, String> {
    let mut buf = [0u8; 4];
    stdin
        .read_exact(&mut buf)
        .map_err(|e| format!("read len: {e}"))?;
    Ok(u32::from_be_bytes(buf))
}

fn read_blob(stdin: &mut impl Read) -> Result<Vec<u8>, String> {
    let n = read_u32_be(stdin)? as usize;
    if n > 16 * 1024 * 1024 {
        return Err("blob too large".into());
    }
    let mut v = vec![0u8; n];
    if n > 0 {
        stdin
            .read_exact(&mut v)
            .map_err(|e| format!("read blob: {e}"))?;
    }
    Ok(v)
}

fn run_guest(guest_id: &str, public: &[u8], secret: &[u8], extra: &[u8]) -> Result<Vec<u8>, String> {
    if guest_id == RUNTIME_GUEST_ID {
        if extra.is_empty() {
            return Err("guest_prog_runtime requires program in extra blob".into());
        }
        // Program is public measurement material; secret is private payload digested only.
        guest_prog_run(extra, public)
    } else {
        // Secret holds private rules; public holds action framing.
        let rules = if secret.is_empty() { extra } else { secret };
        let rh = sha256(rules);
        run_guest_id(guest_id, &rh, public, Some(rules))
    }
}

fn main() {
    harden_against_weaker_agents();

    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let hex_out = args.first().map(|s| s.as_str()) == Some("--hex-out");
    if hex_out {
        args.remove(0);
    }
    let guest_id = args
        .first()
        .cloned()
        .unwrap_or_else(|| "compliance_operator".into());

    let mut stdin = std::io::stdin().lock();
    let public = match read_blob(&mut stdin) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("sealed_worker: {e}");
            process::exit(2);
        }
    };
    let mut secret = Zeroizing::new(match read_blob(&mut stdin) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("sealed_worker: {e}");
            process::exit(2);
        }
    });
    let extra = match read_blob(&mut stdin) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("sealed_worker: {e}");
            process::exit(2);
        }
    };

    let digest = sha256(secret.as_slice());
    let outputs = match run_guest(&guest_id, &public, secret.as_slice(), &extra) {
        Ok(o) => o,
        Err(e) => {
            // Never print secret material.
            eprintln!("sealed_worker: guest error");
            let _ = e;
            secret.zeroize();
            process::exit(3);
        }
    };

    // Scrub secret before writing any response.
    secret.zeroize();

    // Refuse to echo if outputs somehow contain non-hex binary equal to digest only check:
    // parent also checks UTF-8 leak.

    if hex_out {
        println!("OK");
        println!("outputs_hex={}", hex_encode(&outputs));
        println!("digest_hex={}", hex_encode(&digest));
    } else {
        let mut stdout = std::io::stdout().lock();
        let len = (outputs.len() as u32).to_be_bytes();
        let _ = stdout.write_all(&len);
        let _ = stdout.write_all(&outputs);
        let _ = stdout.write_all(&digest);
        let _ = stdout.write_all(&[0u8]);
        let _ = stdout.flush();
    }
}
