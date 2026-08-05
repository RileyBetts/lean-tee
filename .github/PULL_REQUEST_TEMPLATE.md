## Summary

<!-- Why this change exists (not just what). -->

## Test plan

- [ ] Mock path: `bash scripts/ci.sh` (or relevant demos) when touching receipts / guests / gRPC
- [ ] Rust: `cd host && cargo test -p lean_tee_receipt -p lean_tee_compliance` if host crypto/guests change
- [ ] SP1: note `sp1-execute` impact if guest/runtime/digests change
- [ ] Docs/proto updated if wire or Accept semantics change

## Checklist

- [ ] No secrets / `.env` / build artifacts committed
- [ ] SPDX Apache-2.0 on new first-party source files
- [ ] Read [CONTRIBUTING.md](../CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md)
- [ ] Security-sensitive? Prefer private report per [SECURITY.md](../SECURITY.md)
