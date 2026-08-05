/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Guest
import LeanTee.Receipt
import LeanTee.Hash

open LeanTee

def expectReject (d : ReceiptDecision) (wantPrefix : String) (label : String) : IO Unit := do
  match d with
  | .accept => throw (IO.userError s!"{label}: expected reject starting with {wantPrefix}")
  | .reject reason =>
    if !reason.startsWith wantPrefix then
      throw (IO.userError s!"{label}: want prefix `{wantPrefix}` got `{reason}`")

def expectAccept (d : ReceiptDecision) (label : String) : IO Unit := do
  if !TeeReceipt.isAccept d then
    throw (IO.userError s!"{label}: expected accept")

def main : IO Unit := do
  let rules := "allow=vote.yes,vote.no\n".toUTF8
  let cfgHash := Hash.sha256 rules
  let m : Measurement := { codeHash := Guest.demoCodeHash, configHash := cfgHash }
  let inputs := Guest.bindInteraction "vote.yes" "adv-1" ""
  let outputs := Guest.runCompliance { rulesHash := cfgHash, rulesRaw := rules } inputs
  let nonce := Hash.sha256 (Hash.concatLenPrefixed #[inputs, cfgHash])
  let proof := Guest.mockProof m inputs outputs
  let r := TeeReceipt.withComputedHash {
    measurement := m
    publicIO := { inputs, outputs }
    resultHash := ByteArray.empty
    nonce
    proofRef := proof
    receiptMeta := ReceiptMeta.default
  }
  let policy := MeasurementPolicy.singleton m

  expectAccept (TeeReceipt.acceptReceipt policy r true) "honest"
  expectAccept (TeeReceipt.acceptReceipt policy { r with receiptMeta := { r.receiptMeta with cryptoSuite := "" } } true)
    "empty suite"

  -- Field mutations (resultHash left stale → mismatch)
  expectReject
    (TeeReceipt.acceptReceipt policy
      { r with publicIO := { inputs, outputs := "decision=allow\nforged\n".toUTF8 } } true)
    "resultHash mismatch" "outputs"
  expectReject
    (TeeReceipt.acceptReceipt policy
      { r with publicIO := { inputs := "action=vote.no\n".toUTF8, outputs } } true)
    "resultHash mismatch" "inputs"
  expectReject
    (TeeReceipt.acceptReceipt policy { r with nonce := "tampered-nonce".toUTF8 } true)
    "resultHash mismatch" "nonce"
  expectReject
    (TeeReceipt.acceptReceipt policy
      { r with resultHash := Hash.sha256 "wrong-evidence".toUTF8 } true)
    "resultHash mismatch" "evidence"
  expectReject
    (TeeReceipt.acceptReceipt policy
      { r with proofRef := Hash.sha256 "wrong-proof".toUTF8 } false)
    "proof invalid" "proofOk=false"
  -- Mock digest check (what teeServer handleAccept uses) rejects bad proof_ref
  if Guest.verifyMockProof m inputs outputs (Hash.sha256 "wrong-proof".toUTF8) then
    throw (IO.userError "bad proof_ref must fail verifyMockProof")

  -- Wrong measurement vs policy
  let evilM := { m with codeHash := Hash.sha256 "evil".toUTF8 }
  expectReject
    (TeeReceipt.acceptReceipt policy { r with measurement := evilM } true)
    "measurement not in policy" "codeHash"
  let evilCfg := { m with configHash := Hash.sha256 "other-rules".toUTF8 }
  expectReject
    (TeeReceipt.acceptReceipt policy { r with measurement := evilCfg } true)
    "measurement not in policy" "configHash"

  -- Suite fail-closed
  expectReject
    (TeeReceipt.acceptReceipt policy
      { r with receiptMeta := { r.receiptMeta with cryptoSuite := suiteBlake3Mock } } true)
    "unsupported crypto_suite=" "blake3"
  expectReject
    (TeeReceipt.acceptReceipt policy
      { r with receiptMeta := { r.receiptMeta with cryptoSuite := "nope" } } true)
    "unsupported crypto_suite=" "unknown"

  IO.println "adversarialMatrix OK"
