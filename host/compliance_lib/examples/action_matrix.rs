// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

use lean_tee_compliance::{
    resolve_guest, run_guest, BUILTIN, COMPLIANCE, ONBOARDING, TRADE, VOTING,
};
use lean_tee_receipt::{sha256, CryptoSuite};

fn expect_guest(guest_id: &str, action: &str, want: &str) {
    let g = resolve_guest(guest_id).unwrap();
    let rules = b"rules\n";
    let rh = sha256(rules);
    let inputs = format!("action={action}\n").into_bytes();
    let out = run_guest(g, &rh, &inputs, Some(rules), CryptoSuite::Sha256Mock);
    let s = String::from_utf8(out).unwrap();
    assert!(
        s.starts_with(&format!("decision={want}\n")),
        "guest={guest_id} action={action} want={want} got={s}"
    );
    println!("rs {guest_id} {action} -> {want}");
}

fn main() {
    for g in BUILTIN {
        println!("guest {} code_id={}", g.guest_id, String::from_utf8_lossy(g.code_id));
    }
    expect_guest(COMPLIANCE.guest_id, "vote.yes", "allow");
    expect_guest(VOTING.guest_id, "vote.yes", "allow");
    expect_guest(VOTING.guest_id, "trade.submit", "deny");
    expect_guest(ONBOARDING.guest_id, "supplier.register", "allow");
    expect_guest(ONBOARDING.guest_id, "vote.yes", "deny");
    expect_guest(TRADE.guest_id, "trade.submit", "allow");
    expect_guest(TRADE.guest_id, "vote.yes", "deny");
    println!("action_matrix rust OK");
}
