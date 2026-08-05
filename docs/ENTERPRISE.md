# lean-tee enterprise packaging

Integrity-only enterprise control plane. **No sealed memory** — inputs/outputs in receipts are public.

## Production checklist

| Item | Env / artifact | Notes |
| --- | --- | --- |
| Guests | `LEAN_TEE_GUESTS_FILE` → [`config/guests/registry.json`](../config/guests/registry.json) | Builtin registry if unset |
| Measurement policy | `LEAN_TEE_POLICY_FILE` | `codeHex configHex` lines |
| Tenant ACL | `LEAN_TEE_ACL_FILE` → [`config/acl.example.txt`](../config/acl.example.txt) | tenant → allowed `guest_id`s; optional `load_program` tenants |
| API key | `LEAN_TEE_API_KEY` | Clients send `LEAN_TEE_API_KEY` env to CLI/SDK; server rejects mismatch when set |
| Audit | `LEAN_TEE_AUDIT_FILE` | Append-only JSONL Accept/Execute/LoadProgram events |
| Quotas | `LEAN_TEE_MAX_RPS`, `LEAN_TEE_MAX_INFLIGHT` | Per-process limits (default unlimited if unset) |
| Job durability | `LEAN_TEE_JOB_DIR` | Persist receipts by `job_id` |
| Prove profile | `LEAN_TEE_DEFAULT_PROFILE=lean-tee-v2` | **Production default**; mock (`lean-tee-v1`) only in CI |
| GuestProg size | `LEAN_TEE_MAX_PROGRAM_BYTES` | Default 65536; LoadProgram / Execute reject larger |
| Local confidentiality | `LEAN_TEE_CONFIDENTIALITY=local` + `LEAN_TEE_SEALED_WORKER` | Optional; see [CONFIDENTIALITY.md](CONFIDENTIALITY.md) — not Nitro |
| Host SP1 trust | `LEAN_TEE_TRUST_PROOF_OK=1` | Only on trusted host adapters |
| Metrics | `LEAN_TEE_METRICS=1` | Log counters on Execute/Accept |

## mTLS (recommended)

Terminate TLS at a reverse proxy (Envoy / nginx / AWS ALB) in front of h2c `teeServer`:

```text
Client --mTLS--> Envoy:443 --h2c--> teeServer:50071
```

Require client certs mapped to a tenant id; pass tenant via `LEAN_TEE_TENANT` in the app environment, or terminate auth at the proxy and set `LEAN_TEE_API_KEY` per environment.

lean-grpc v1.1.0 local demos use h2c; do not expose h2c on the public internet.

ACL file format (Lean parser): [`config/acl.example.txt`](../config/acl.example.txt). JSON sketch for docs: [`config/acl.example.json`](../config/acl.example.json).

## AuthZ model

1. If `LEAN_TEE_API_KEY` is set, request must present the same key (SDK/CLI env).
2. If `LEAN_TEE_ACL_FILE` is set, `LEAN_TEE_TENANT` must be allowed to use the requested `guest_id`.
3. If the ACL contains any `load_program <tenant>...` lines, only those tenants may call `LoadProgram`.
4. If the ACL contains any `secret_inputs <tenant>...` lines, only those tenants may send `Execute.secret_inputs` (requires `LEAN_TEE_CONFIDENTIALITY=local`).
5. Measurement policy still applies on Accept.
6. GuestProg bytes must parse and stay under `LEAN_TEE_MAX_PROGRAM_BYTES`.

## Audit JSONL

Each line is one JSON object, for example:

```json
{"ts":"ISO-8601","event":"accept","accepted":true,"reason":"","guest_id":"voting_operator","result_hash_hex":"...","tenant":"demo"}
```

Do not treat audit as confidentiality — it may include public I/O digests only by default (result hash / guest id).

## Quotas

- `LEAN_TEE_MAX_RPS` — approximate Execute accepts per rolling second.
- `LEAN_TEE_MAX_INFLIGHT` — max concurrent Execute handlers (best-effort in-process).

Exceeding quota returns gRPC resource-exhausted style error status where supported, else Execute `status=error:quota`.
