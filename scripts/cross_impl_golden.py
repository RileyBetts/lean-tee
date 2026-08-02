#!/usr/bin/env python3
"""Cross-impl golden: verify testdata goldens with the Python twin."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "clients" / "python"))

from lean_tee import TeeReceipt, accept_receipt  # noqa: E402

DATA = ROOT / "testdata"


def check(name: str, *, require_blake3: bool) -> None:
    path = DATA / name
    raw = json.loads(path.read_text())
    suite = raw.get("crypto_suite", "")
    if suite == "blake3+mock":
        try:
            import blake3  # noqa: F401
        except ImportError:
            if require_blake3:
                raise SystemExit("blake3 package required for golden_blake3_mock.json")
            print(f"python skip {name} (blake3 pkg absent)")
            return
    r = TeeReceipt.from_hex(raw)
    ok, why = accept_receipt(r)
    if not ok:
        raise SystemExit(f"python {name}: {why}")
    print(f"python {name} OK suite={r.crypto_suite}")


def main() -> None:
    require = "--require-blake3" in sys.argv
    check("golden_v1.json", require_blake3=False)
    check("golden_blake3_mock.json", require_blake3=require)
    print("cross_impl_golden python OK")


if __name__ == "__main__":
    main()
