/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Guest
import LeanTee.Hash
import LeanTee.Receipt

/-- Emit / check golden vectors for Rust `lean_tee_receipt` parity. -/
def main : IO Unit := do
  let rules := "allow=vote.yes,vote.no\n".toUTF8
  let config := LeanTee.Hash.sha256 rules
  let inputs := LeanTee.Guest.bindInteraction "vote.yes" "golden-1" ""
  let outputs := LeanTee.Guest.runCompliance { rulesHash := config, rulesRaw := rules } inputs
  let nonce := LeanTee.Hash.sha256 (LeanTee.Hash.concatLenPrefixed #[inputs, config])
  let m : LeanTee.Measurement := {
    codeHash := LeanTee.Guest.demoCodeHash
    configHash := config
  }
  let proof := LeanTee.Guest.mockProof m inputs outputs
  let receipt := LeanTee.TeeReceipt.withComputedHash {
    measurement := m
    publicIO := { inputs, outputs }
    resultHash := ByteArray.empty
    nonce
    proofRef := proof
    receiptMeta := LeanTee.ReceiptMeta.default
  }
  let expectCode := "bec5a1b6fd790b3332da9ebdd744dbe4d58612fa9de64321298ddea05a40784f"
  let gotCode := LeanTee.Guest.hexEncode m.codeHash
  if gotCode ≠ expectCode then
    throw (IO.userError s!"code_hash mismatch got={gotCode}")
  let expectEv := "198ed26a905540074fe9a33b1dd45cb45e758578e1e4dd4402a50492788661bc"
  let gotEv := LeanTee.Guest.hexEncode receipt.resultHash
  if gotEv ≠ expectEv then
    throw (IO.userError s!"evidence mismatch got={gotEv}")
  let expectProof := "43c5b69cfc6fbd6bf251c6f748c599f5cb4c8897599a59fb7fa7dce925b9a81b"
  let gotProof := LeanTee.Guest.hexEncode proof
  if gotProof ≠ expectProof then
    throw (IO.userError s!"proof mismatch got={gotProof}")
  if receipt.receiptMeta.cryptoSuite ≠ LeanTee.suiteSha256Mock then
    throw (IO.userError s!"crypto_suite got={receipt.receiptMeta.cryptoSuite}")
  IO.println "goldenVectors OK"
