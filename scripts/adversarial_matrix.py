# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

#!/usr/bin/env python3
"""Adversarial receipt mutations against the Python twin."""

from __future__ import annotations

import copy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "clients" / "python"))

from lean_tee import (  # noqa: E402
    SUITE_BLAKE3_MOCK,
    SUITE_SHA256_MOCK,
    TeeReceipt,
    accept_receipt,
    execute_local,
    normalize_suite,
)


def expect_fail(r: TeeReceipt, want: str, label: str) -> None:
    ok, why = accept_receipt(r)
    if ok:
        raise SystemExit(f"{label}: expected fail containing {want!r}")
    if want not in why:
        raise SystemExit(f"{label}: want {want!r} in {why!r}")


def main() -> None:
    rules = b"allow=vote.yes,vote.no\n"
    r = execute_local("vote.yes", rules, interaction_id="adv-py-1")
    ok, why = accept_receipt(r)
    assert ok, why

    empty = TeeReceipt.from_hex({k: v for k, v in r.as_hex().items() if k != "crypto_suite"})
    assert normalize_suite(empty.crypto_suite) == SUITE_SHA256_MOCK
    ok, why = accept_receipt(empty)
    assert ok, why

    bad = copy.copy(r)
    bad.outputs = b"decision=allow\nforged\n"
    expect_fail(bad, "resultHash mismatch", "outputs")

    bad = copy.copy(r)
    bad.inputs = b"action=vote.no\n"
    expect_fail(bad, "resultHash mismatch", "inputs")

    bad = copy.copy(r)
    bad.nonce = b"tampered-nonce"
    expect_fail(bad, "resultHash mismatch", "nonce")

    bad = copy.copy(r)
    bad.result_hash = b"\x00" * 32
    expect_fail(bad, "resultHash mismatch", "evidence")

    bad = copy.copy(r)
    bad.proof_ref = b"\x11" * 32
    expect_fail(bad, "proof invalid", "proof")

    bad = copy.copy(r)
    bad.code_hash = b"\x22" * 32
    expect_fail(bad, "resultHash mismatch", "code_hash")

    bad = copy.copy(r)
    bad.config_hash = b"\x33" * 32
    expect_fail(bad, "resultHash mismatch", "config_hash")

    bad = copy.copy(r)
    bad.crypto_suite = SUITE_BLAKE3_MOCK
    ok, why = accept_receipt(bad)
    if ok:
        raise SystemExit("suite confusion: expected fail")
    # Without blake3 pkg: ImportError message; with it: resultHash mismatch
    if "resultHash mismatch" not in why and "blake3" not in why.lower():
        raise SystemExit(f"suite confusion: unexpected {why!r}")
    print("suite confusion OK")

    bad = copy.copy(r)
    bad.crypto_suite = "nope"
    expect_fail(bad, "unknown crypto_suite", "unknown suite")

    print("adversarial_matrix python OK")


if __name__ == "__main__":
    main()
