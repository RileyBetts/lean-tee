#!/usr/bin/env python3
"""lean-tee Python SDK — local twin + live teeClient Execute / Accept helpers."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[2]
_HOST_RECEIPT = _ROOT / "host" / "receipt"

CODE_ID = b"lean-tee/compliance_operator/v1"
DEFAULT_ALLOW = (
    "action=vote.yes",
    "action=vote.no",
    "action=supplier.register",
    "action=purchaser.approve",
    "action=purchaser.reject",
    "action=trade.submit",
)


def sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def code_hash() -> bytes:
    return sha256(CODE_ID)


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


def resolve_allow(rules: bytes | None, inputs: bytes) -> list[str]:
    if rules:
        p = parse_allow(rules.decode("utf-8", errors="replace"))
        if p:
            return p
    p = parse_allow(inputs.decode("utf-8", errors="replace"))
    return p or list(DEFAULT_ALLOW)


def run_compliance(rules_hash: bytes, inputs: bytes, rules: bytes | None = None) -> bytes:
    text = inputs.decode("utf-8", errors="replace")
    allowed = any(text.startswith(p) for p in resolve_allow(rules, inputs))
    decision = "allow" if allowed else "deny"
    reason = sha256(concat_len_prefixed([rules_hash, inputs]))
    return f"decision={decision}\nreason={reason.hex()}\n".encode()


def mock_proof(code: bytes, config: bytes, inputs: bytes, outputs: bytes) -> bytes:
    return sha256(
        concat_len_prefixed([b"lean-tee/mock-proof/v1", code, config, inputs, outputs])
    )


def result_hash(
    code: bytes, config: bytes, inputs: bytes, outputs: bytes, nonce: bytes
) -> bytes:
    return sha256(
        concat_len_prefixed([b"lean-tee/v1", code, config, inputs, outputs, nonce])
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

    def as_hex(self) -> dict[str, str]:
        return {
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
        )


def execute_local(
    action: str,
    rules: bytes,
    *,
    interaction_id: str | None = None,
    nonce: bytes | None = None,
) -> TeeReceipt:
    if interaction_id:
        inputs = bind_interaction(action, interaction_id)
    else:
        inputs = f"action={action}\n".encode()
    config = sha256(rules)
    code = code_hash()
    outputs = run_compliance(config, inputs, rules)
    if nonce is None:
        nonce = sha256(concat_len_prefixed([inputs, config]))
    proof = mock_proof(code, config, inputs, outputs)
    rh = result_hash(code, config, inputs, outputs, nonce)
    return TeeReceipt(code, config, inputs, outputs, nonce, rh, proof)


def _tee_client_bin() -> Path:
    env = os.environ.get("LEAN_TEE_CLIENT")
    if env:
        return Path(env)
    return _ROOT / ".lake" / "build" / "bin" / "teeClient"


def execute_live(action: str, rules: bytes, addr: str) -> TeeReceipt:
    client = _tee_client_bin()
    if not client.is_file():
        raise FileNotFoundError(f"teeClient not found at {client}")
    with tempfile.NamedTemporaryFile(prefix="lean-tee-rules-", delete=False) as tf:
        tf.write(rules)
        path = tf.name
    try:
        out = subprocess.check_output([str(client), addr, action, path], text=True).strip()
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
) -> TeeReceipt:
    addr = os.environ.get("LEAN_TEE_ADDR", "").strip()
    if addr:
        if nonce is not None or interaction_id is not None:
            # live teeClient currently takes action only; prefer local for binding
            if interaction_id is not None:
                return execute_local(action, rules, interaction_id=interaction_id, nonce=nonce)
        return execute_live(action, rules, addr)
    return execute_local(action, rules, interaction_id=interaction_id, nonce=nonce)


def accept_receipt(r: TeeReceipt) -> tuple[bool, str]:
    if r.result_hash != result_hash(
        r.code_hash, r.config_hash, r.inputs, r.outputs, r.nonce
    ):
        return False, "resultHash mismatch"
    if r.proof_ref != mock_proof(r.code_hash, r.config_hash, r.inputs, r.outputs):
        return False, "proof invalid"
    return True, ""


def execute_vote(action: str, rules: bytes, nonce: bytes | None = None) -> TeeReceipt:
    return execute_action(action, rules, nonce=nonce)
