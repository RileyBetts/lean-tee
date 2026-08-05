# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

"""Golden vectors mirroring Tests/GoldenVectors.lean and testdata/*.json."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from lean_tee import (
    SUITE_SHA256_MOCK,
    TeeReceipt,
    accept_receipt,
    bind_interaction,
    code_hash,
    concat_len_prefixed,
    execute_local,
    hash_suite,
    mock_proof,
    result_hash,
    run_compliance,
)

ROOT = Path(__file__).resolve().parents[3]
TESTDATA = ROOT / "testdata"

GOLDEN_CODE = "bec5a1b6fd790b3332da9ebdd744dbe4d58612fa9de64321298ddea05a40784f"
GOLDEN_EVIDENCE = "198ed26a905540074fe9a33b1dd45cb45e758578e1e4dd4402a50492788661bc"
GOLDEN_PROOF = "43c5b69cfc6fbd6bf251c6f748c599f5cb4c8897599a59fb7fa7dce925b9a81b"


def test_golden_vectors_from_scratch() -> None:
    """Same construction as Tests/GoldenVectors.lean."""
    rules = b"allow=vote.yes,vote.no\n"
    config = hash_suite(SUITE_SHA256_MOCK, rules)
    inputs = bind_interaction("vote.yes", "golden-1", "")
    outputs = run_compliance(config, inputs, rules, suite=SUITE_SHA256_MOCK)
    nonce = hash_suite(SUITE_SHA256_MOCK, concat_len_prefixed([inputs, config]))
    code = code_hash(SUITE_SHA256_MOCK)
    proof = mock_proof(code, config, inputs, outputs, suite=SUITE_SHA256_MOCK)
    evidence = result_hash(code, config, inputs, outputs, nonce, suite=SUITE_SHA256_MOCK)

    assert code.hex() == GOLDEN_CODE
    assert evidence.hex() == GOLDEN_EVIDENCE
    assert proof.hex() == GOLDEN_PROOF

    receipt = TeeReceipt(code, config, inputs, outputs, nonce, evidence, proof, SUITE_SHA256_MOCK)
    ok, why = accept_receipt(receipt)
    assert ok, why


def test_golden_v1_json_fixture() -> None:
    raw = json.loads((TESTDATA / "golden_v1.json").read_text())
    receipt = TeeReceipt.from_hex(raw)
    ok, why = accept_receipt(receipt)
    assert ok, why
    assert receipt.crypto_suite == SUITE_SHA256_MOCK


def test_golden_blake3_json_fixture() -> None:
    pytest.importorskip("blake3")
    raw = json.loads((TESTDATA / "golden_blake3_mock.json").read_text())
    receipt = TeeReceipt.from_hex(raw)
    ok, why = accept_receipt(receipt)
    assert ok, why


def test_execute_local_matches_golden_evidence() -> None:
    rules = b"allow=vote.yes,vote.no\n"
    receipt = execute_local(
        "vote.yes",
        rules,
        interaction_id="golden-1",
        suite=SUITE_SHA256_MOCK,
    )
    assert receipt.result_hash.hex() == GOLDEN_EVIDENCE
    ok, why = accept_receipt(receipt)
    assert ok, why


def test_tampered_receipt_rejected() -> None:
    rules = b"allow=vote.yes,vote.no\n"
    receipt = execute_local("vote.yes", rules)
    bad = TeeReceipt(
        code_hash=receipt.code_hash,
        config_hash=receipt.config_hash,
        inputs=receipt.inputs,
        outputs=b"decision=allow\nforged\n",
        nonce=receipt.nonce,
        result_hash=receipt.result_hash,
        proof_ref=receipt.proof_ref,
        crypto_suite=receipt.crypto_suite,
    )
    ok, why = accept_receipt(bad)
    assert not ok
    assert why == "resultHash mismatch"
