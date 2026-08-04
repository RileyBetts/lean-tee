# Published SP1 guest digests

`sp1_guest_digests.json` pins the measured Lean SP1 executable (`lean_tee_guest_lean`):

- `elf_sha256` — SHA-256 of ELF bytes
- `vk_hash_bytes` / `vk_bytes32` — SP1 verifying-key digests

Wire `Measurement` remains `codeHash` + `configHash` only. Regenerate after guest/runtime changes:

```bash
bash scripts/sp1_guest_digest.sh
```

Also produced by `scripts/sp1_execute_ci.sh` and uploaded from the `sp1-execute` workflow.
