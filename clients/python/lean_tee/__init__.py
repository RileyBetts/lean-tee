#!/usr/bin/env python3
"""lean-tee Python SDK — local twin + live teeClient Execute / Accept helpers."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[2]
_HOST_RECEIPT = _ROOT / "host" / "receipt"

CODE_ID = b"lean-tee/compliance_operator/lean-sp1/v1"
SUITE_SHA256_MOCK = "sha256+mock"
SUITE_SHA256_SP1 = "sha256+sp1"
SUITE_BLAKE3_MOCK = "blake3+mock"
PROFILE_V1 = "lean-tee-v1"
PROFILE_V2 = "lean-tee-v2"

RESULT_DOMAIN_SHA256 = b"lean-tee/v1"
MOCK_PROOF_DOMAIN_SHA256 = b"lean-tee/mock-proof/v1"
RESULT_DOMAIN_BLAKE3 = b"lean-tee/blake3/v1"
MOCK_PROOF_DOMAIN_BLAKE3 = b"lean-tee/mock-proof-blake3/v1"

DEFAULT_ALLOW = (
    "action=vote.yes",
    "action=vote.no",
    "action=supplier.register",
    "action=purchaser.approve",
    "action=purchaser.reject",
    "action=trade.submit",
)

# First-party guests (mirrors config/guests/registry.json)
GUESTS: dict[str, dict] = {
    "compliance_operator": {
        "code_id": b"lean-tee/compliance_operator/lean-sp1/v1",
        "actions": [
            "vote.yes",
            "vote.no",
            "supplier.register",
            "purchaser.approve",
            "purchaser.reject",
            "trade.submit",
        ],
    },
    "voting_operator": {
        "code_id": b"lean-tee/voting_operator/lean-sp1/v1",
        "actions": ["vote.yes", "vote.no"],
    },
    "onboarding_operator": {
        "code_id": b"lean-tee/onboarding_operator/lean-sp1/v1",
        "actions": ["supplier.register", "purchaser.approve", "purchaser.reject"],
    },
    "trade_operator": {
        "code_id": b"lean-tee/trade_operator/lean-sp1/v1",
        "actions": ["trade.submit"],
    },
}


def normalize_guest_id(guest_id: str | None) -> str:
    t = (guest_id or "").strip()
    if not t or t == "compliance_operator/v1":
        return "compliance_operator"
    return t


def resolve_guest(guest_id: str | None) -> dict:
    gid = normalize_guest_id(guest_id)
    if gid not in GUESTS:
        raise ValueError(f"unknown guest_id={gid}")
    return GUESTS[gid]


def normalize_suite(s: str) -> str:
    t = (s or "").strip()
    if not t or t == PROFILE_V1:
        return SUITE_SHA256_MOCK
    if t == PROFILE_V2:
        return SUITE_SHA256_SP1
    return t


def sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def blake3_hash(data: bytes) -> bytes:
    try:
        import blake3  # type: ignore
    except ImportError as e:
        raise ImportError(
            "blake3 package required for blake3+mock; pip install blake3"
        ) from e
    return blake3.blake3(data).digest()


def hash_suite(suite: str, data: bytes) -> bytes:
    n = normalize_suite(suite)
    if n in (SUITE_SHA256_MOCK, SUITE_SHA256_SP1):
        return sha256(data)
    if n == SUITE_BLAKE3_MOCK:
        return blake3_hash(data)
    raise ValueError(f"unknown crypto_suite={n}")


def result_domain(suite: str) -> bytes:
    n = normalize_suite(suite)
    if n in (SUITE_SHA256_MOCK, SUITE_SHA256_SP1):
        return RESULT_DOMAIN_SHA256
    if n == SUITE_BLAKE3_MOCK:
        return RESULT_DOMAIN_BLAKE3
    raise ValueError(f"unknown crypto_suite={n}")


def mock_domain(suite: str) -> bytes | None:
    n = normalize_suite(suite)
    if n == SUITE_SHA256_MOCK:
        return MOCK_PROOF_DOMAIN_SHA256
    if n == SUITE_BLAKE3_MOCK:
        return MOCK_PROOF_DOMAIN_BLAKE3
    if n == SUITE_SHA256_SP1:
        return None
    raise ValueError(f"unknown crypto_suite={n}")


def code_hash(suite: str = SUITE_SHA256_MOCK, guest_id: str | None = None) -> bytes:
    g = resolve_guest(guest_id)
    return hash_suite(suite, g["code_id"])


def concat_len_prefixed(chunks: list[bytes]) -> bytes:
    out = bytearray()
    for c in chunks:
        out.extend(len(c).to_bytes(4, "big"))
        out.extend(c)
    return bytes(out)


def bind_interaction(action: str, interaction_id: str, payload: str = "") -> bytes:
    s = f"action={action}\ninteraction={interaction_id}\n"
    if payload:
        s += payload if payload.endswith("\n") else payload + "\n"
    return s.encode()


def parse_allow(text: str) -> list[str] | None:
    for line in text.splitlines():
        t = line.strip()
        if t.startswith("allow="):
            parts = []
            for p in t[6:].split(","):
                p = p.strip()
                if not p:
                    continue
                parts.append(p if p.startswith("action=") else f"action={p}")
            return parts or None
    return None


def resolve_allow(
    rules: bytes | None,
    inputs: bytes,
    *,
    guest_id: str | None = None,
) -> list[str]:
    g = resolve_guest(guest_id)
    builtin = [f"action={a}" for a in g["actions"]]
    asked = None
    if rules:
        asked = parse_allow(rules.decode("utf-8", errors="replace"))
    if asked is None:
        asked = parse_allow(inputs.decode("utf-8", errors="replace"))
    if asked:
        filtered = [p for p in asked if p in builtin]
        return filtered or builtin
    return builtin


def run_compliance(
    rules_hash: bytes,
    inputs: bytes,
    rules: bytes | None = None,
    *,
    suite: str = SUITE_SHA256_MOCK,
    guest_id: str | None = None,
) -> bytes:
    text = inputs.decode("utf-8", errors="replace")
    allowed = any(text.startswith(p) for p in resolve_allow(rules, inputs, guest_id=guest_id))
    decision = "allow" if allowed else "deny"
    reason = hash_suite(suite, concat_len_prefixed([rules_hash, inputs]))
    return f"decision={decision}\nreason={reason.hex()}\n".encode()


def mock_proof(
    code: bytes,
    config: bytes,
    inputs: bytes,
    outputs: bytes,
    *,
    suite: str = SUITE_SHA256_MOCK,
) -> bytes:
    domain = mock_domain(suite)
    if domain is None:
        raise ValueError(f"suite {normalize_suite(suite)} has no mock proof")
    return hash_suite(
        suite, concat_len_prefixed([domain, code, config, inputs, outputs])
    )


def result_hash(
    code: bytes,
    config: bytes,
    inputs: bytes,
    outputs: bytes,
    nonce: bytes,
    *,
    suite: str = SUITE_SHA256_MOCK,
) -> bytes:
    return hash_suite(
        suite,
        concat_len_prefixed(
            [result_domain(suite), code, config, inputs, outputs, nonce]
        ),
    )


@dataclass
class TeeReceipt:
    code_hash: bytes
    config_hash: bytes
    inputs: bytes
    outputs: bytes
    nonce: bytes
    result_hash: bytes
    proof_ref: bytes
    crypto_suite: str = field(default=SUITE_SHA256_MOCK)

    def as_hex(self) -> dict[str, str]:
        return {
            "crypto_suite": normalize_suite(self.crypto_suite),
            "code_hash_hex": self.code_hash.hex(),
            "config_hash_hex": self.config_hash.hex(),
            "inputs_hex": self.inputs.hex(),
            "outputs_hex": self.outputs.hex(),
            "nonce_hex": self.nonce.hex(),
            "evidence_root_hex": self.result_hash.hex(),
            "proof_ref_hex": self.proof_ref.hex(),
        }

    @classmethod
    def from_hex(cls, d: dict[str, str]) -> "TeeReceipt":
        return cls(
            code_hash=bytes.fromhex(d["code_hash_hex"]),
            config_hash=bytes.fromhex(d["config_hash_hex"]),
            inputs=bytes.fromhex(d["inputs_hex"]),
            outputs=bytes.fromhex(d["outputs_hex"]),
            nonce=bytes.fromhex(d["nonce_hex"]),
            result_hash=bytes.fromhex(d["evidence_root_hex"]),
            proof_ref=bytes.fromhex(d["proof_ref_hex"]),
            crypto_suite=normalize_suite(d.get("crypto_suite", "")),
        )


def execute_local(
    action: str,
    rules: bytes,
    *,
    interaction_id: str | None = None,
    nonce: bytes | None = None,
    suite: str = SUITE_SHA256_MOCK,
    guest_id: str | None = None,
) -> TeeReceipt:
    suite = normalize_suite(suite)
    gid = normalize_guest_id(guest_id)
    if interaction_id:
        inputs = bind_interaction(action, interaction_id)
    else:
        inputs = f"action={action}\n".encode()
    config = hash_suite(suite, rules)
    code = code_hash(suite, guest_id=gid)
    outputs = run_compliance(config, inputs, rules, suite=suite, guest_id=gid)
    if nonce is None:
        nonce = hash_suite(suite, concat_len_prefixed([inputs, config]))
    proof = mock_proof(code, config, inputs, outputs, suite=suite)
    rh = result_hash(code, config, inputs, outputs, nonce, suite=suite)
    return TeeReceipt(code, config, inputs, outputs, nonce, rh, proof, suite)


def _tee_client_bin() -> Path:
    env = os.environ.get("LEAN_TEE_CLIENT")
    if env:
        return Path(env)
    return _ROOT / ".lake" / "build" / "bin" / "teeClient"


def execute_live(
    action: str, rules: bytes, addr: str, *, guest_id: str | None = None
) -> TeeReceipt:
    client = _tee_client_bin()
    if not client.is_file():
        raise FileNotFoundError(f"teeClient not found at {client}")
    with tempfile.NamedTemporaryFile(prefix="lean-tee-rules-", delete=False) as tf:
        tf.write(rules)
        path = tf.name
    try:
        cmd = [str(client), addr, action, path]
        gid = normalize_guest_id(guest_id)
        if gid and gid != "compliance_operator":
            cmd.append(gid)
        elif os.environ.get("LEAN_TEE_GUEST_ID"):
            cmd.append(os.environ["LEAN_TEE_GUEST_ID"])
        out = subprocess.check_output(cmd, text=True).strip()
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    return TeeReceipt.from_hex(json.loads(out))


def execute_action(
    action: str,
    rules: bytes,
    *,
    interaction_id: str | None = None,
    nonce: bytes | None = None,
    suite: str = SUITE_SHA256_MOCK,
    guest_id: str | None = None,
) -> TeeReceipt:
    addr = os.environ.get("LEAN_TEE_ADDR", "").strip()
    gid = guest_id if guest_id is not None else os.environ.get("LEAN_TEE_GUEST_ID")
    if addr:
        if nonce is not None or interaction_id is not None:
            if interaction_id is not None:
                return execute_local(
                    action,
                    rules,
                    interaction_id=interaction_id,
                    nonce=nonce,
                    suite=suite,
                    guest_id=gid,
                )
        return execute_live(action, rules, addr, guest_id=gid)
    return execute_local(
        action, rules, interaction_id=interaction_id, nonce=nonce, suite=suite, guest_id=gid
    )


def accept_receipt(r: TeeReceipt) -> tuple[bool, str]:
    try:
        suite = normalize_suite(r.crypto_suite)
        if mock_domain(suite) is None:
            return False, f"suite {suite} is not mock; use host SP1 verify path"
        if r.result_hash != result_hash(
            r.code_hash,
            r.config_hash,
            r.inputs,
            r.outputs,
            r.nonce,
            suite=suite,
        ):
            return False, "resultHash mismatch"
        if r.proof_ref != mock_proof(
            r.code_hash, r.config_hash, r.inputs, r.outputs, suite=suite
        ):
            return False, "proof invalid"
        return True, ""
    except (ValueError, ImportError) as e:
        return False, str(e)


def execute_vote(action: str, rules: bytes, nonce: bytes | None = None) -> TeeReceipt:
    return execute_action(action, rules, nonce=nonce)
