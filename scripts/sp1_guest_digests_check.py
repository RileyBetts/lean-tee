#!/usr/bin/env python3
# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

"""Compare regenerated SP1 guest digests against the pinned artifact in git."""

from __future__ import annotations

import json
import sys
from pathlib import Path

PIN_FIELDS = ("code_hash", "elf_sha256", "vk_hash_bytes", "vk_bytes32", "sp1_version")


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def main() -> None:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} PINNED.json ACTUAL.json", file=sys.stderr)
        raise SystemExit(2)
    pinned = load(Path(sys.argv[1]))
    actual = load(Path(sys.argv[2]))
    errors: list[str] = []
    for key in PIN_FIELDS:
        want = pinned.get(key)
        got = actual.get(key)
        if want != got:
            errors.append(f"{key}: pinned={want!r} actual={got!r}")
    if errors:
        print("sp1_guest_digests mismatch:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        print(
            "Regenerate with: bash scripts/sp1_guest_digest.sh && commit artifacts/sp1_guest_digests.json",
            file=sys.stderr,
        )
        raise SystemExit(1)
    print("sp1_guest_digests_check OK")


if __name__ == "__main__":
    main()
