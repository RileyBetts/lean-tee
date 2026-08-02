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
  let expectCode := "6c3d3e4ff28fd6b2ce6730c132ef9a34e9d8ab4e3762ba48cca8d3469cce98a0"
  let gotCode := LeanTee.Guest.hexEncode m.codeHash
  if gotCode ≠ expectCode then
    throw (IO.userError s!"code_hash mismatch got={gotCode}")
  let expectEv := "fdef26fe35ecac203ef446343e15e4a314132c7dde456b9e9fd92c1348cf6b72"
  let gotEv := LeanTee.Guest.hexEncode receipt.resultHash
  if gotEv ≠ expectEv then
    throw (IO.userError s!"evidence mismatch got={gotEv}")
  let expectProof := "114d19ddc0fe6872aa5a9ec2179431f30f4b088ea662c3cc22990fe0ef850366"
  let gotProof := LeanTee.Guest.hexEncode proof
  if gotProof ≠ expectProof then
    throw (IO.userError s!"proof mismatch got={gotProof}")
  IO.println "goldenVectors OK"
