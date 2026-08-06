# Local confidentiality (optional)

**Not Nitro. Not a hardware TEE.** Optional `LEAN_TEE_CONFIDENTIALITY=local` keeps secret bytes out of receipts, logs, and `PublicIO` via a **local sealed worker** process.

**Incompatible with `lean-tee-v2` / SP1:** the measured guest cannot see `secret_inputs`, so Execute rejects secrets when the profile is v2. Use **`LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1`** (mock prove). Receipts from this path always use `sha256+mock`.

## Sealed vs public

| Confidential (never in receipt) | Public (receipt-bound) |
| --- | --- |
| Raw rules / PII / keys in `ExecuteRequest.secret_inputs` | `action=` / `interaction=` framing |
| | `secret_digest=<hex>` line in PublicIO.inputs |
| | `decision=…` outputs |
| | `receiptMeta.confidentiality=local` + `secret_digest_hex` |
| | `codeHash` / `configHash` / `resultHash` / `proof_ref` |

Fail closed if raw secrets appear in PublicIO.

## Enable

```bash
cargo build -p lean_tee_confidential --release
export LEAN_TEE_CONFIDENTIALITY=local
export LEAN_TEE_SEALED_WORKER="${CARGO_TARGET_DIR:-$PWD/host/target}/release/sealed_worker"
export LEAN_TEE_DEFAULT_PROFILE=lean-tee-v1   # demos
# optional harden: LEAN_TEE_SEALED_MLOCK=1
lake exe teeServer
```

ACL (optional): `secret_inputs <tenant>…` in [`config/acl.example.txt`](../config/acl.example.txt).

## Demo

```bash
bash scripts/confidentiality_local_demo.sh
```

## Worker hardening (weaker agents)

The `sealed_worker` process:

- Sets `RLIMIT_CORE=0` on Linux and macOS (no core dumps)
- **Linux:** `PR_SET_DUMPABLE=0` (harder unprivileged ptrace / Yama)
- **macOS:** `PT_DENY_ATTACH` (best-effort anti-attach; not Yama-equivalent)
- Zeroizes secret buffers after use
- Never logs secret bytes
- Optional `LEAN_TEE_SEALED_MLOCK=1` (`mlockall`, best-effort)

**Does not** stop local root, kernel malware, or hardware memory inspection.

## Accept

`AcceptReceiptRequest.require_confidentiality=local` requires meta `confidentiality=local` and non-empty `secret_digest_hex`. Integrity still uses hash + proof as usual.

## Honesty

| Claim | True? |
| --- | --- |
| Secrets stay out of portable receipts | Yes (when mode=local) |
| SP1 provides confidentiality | **No** |
| Local worker ≡ Nitro / SEV / TDX | **No** |
| Protects against host root | **No** |

Need hardware sealed RAM → use a real confidential TEE; see [VS_NITRO.md](VS_NITRO.md). lean-tee stays the **public attestation** surface.
