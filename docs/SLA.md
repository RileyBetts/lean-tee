# lean-tee SLA / delivery wording

## What “done” means

`ExecuteResponse.status == "done"` with a filled `receipt` means: the measured guest ran (or mock-ran) on the given public inputs, outputs and proof_ref were bound into `resultHash`, and the job was stored (memory and/or `LEAN_TEE_JOB_DIR`).

It does **not** mean:

- The prover host could not have refused to run (censorship is a non-goal).
- Confidentiality of inputs/outputs.
- Instantaneous prove under SP1 backlog.

## Profiles

| Profile | Expectation |
| --- | --- |
| `lean-tee-v2` (SP1) | **Production default.** Host must verify SP1 before advertising `proof_ref`. Prove latency depends on hardware (`SP1_PROVER`, CPU RAM). Gated CI: weekly SP1 execute-only. |
| `lean-tee-v1` (mock) | **CI/dev only.** Deterministic mock digest. Not production attestation — never the hero path. |

## Durable jobs

With `LEAN_TEE_JOB_DIR` set, completed receipts are written as `<job_id>.json` (hex fields). `GetReceipt` reads memory first, then disk. Retries with the same client-supplied nonce produce a stable `job_id` (hash of nonce ∥ resultHash).

## Prover backlog / censorship

If the Prove backend is down or overloaded, Execute fails with an error status. Clients should retry with backoff. Downstream ledgers must not treat absence of a receipt as acceptance.

## Availability target (guidance)

Single-process `teeServer` is not an HA cluster. For enterprise HA: run N replicas behind the mTLS proxy, shared `LEAN_TEE_JOB_DIR` (NFS/object) or external job store, and a Prove pool. Formal multi-region RPO/RTO is deployment-specific.
