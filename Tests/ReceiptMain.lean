/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Guest
import LeanTee.Receipt
import LeanTee.Hash
import LeanTee.Proto

open LeanTee

def expect (cond : Bool) (msg : String) : IO Unit := do
  if !cond then throw (IO.userError msg)

def main : IO Unit := do
  let rules := "rules=vote.yes,vote.no".toUTF8
  let cfgHash := Hash.sha256 rules
  let m : Measurement := { codeHash := Guest.demoCodeHash, configHash := cfgHash }
  let inputs := "action=vote.yes\n".toUTF8
  let outputs := Guest.runCompliance { rulesHash := cfgHash } inputs
  let nonce := "nonce-1".toUTF8
  let proof := Guest.mockProof m inputs outputs
  let r := TeeReceipt.withComputedHash {
    measurement := m
    publicIO := { inputs, outputs }
    resultHash := ByteArray.empty
    nonce
    proofRef := proof
    receiptMeta := { version := "v1", domain := "lean-tee/v1", sinkId := "" }
  }
  expect (r.resultHash.size == 32) "resultHash must be 32 bytes"
  expect r.hashMatches "hash must match"
  expect (Guest.verifyMockProof m inputs outputs proof) "mock proof ok"

  let policy := MeasurementPolicy.singleton m
  expect (TeeReceipt.isAccept (TeeReceipt.acceptReceipt policy r true)) "should accept"

  -- Adversarial: tamper outputs
  let bad : TeeReceipt := { r with publicIO := { inputs, outputs := "decision=allow\nfaked".toUTF8 } }
  expect (!bad.hashMatches) "tampered outputs break hash"
  expect (!TeeReceipt.isAccept (TeeReceipt.acceptReceipt policy bad true)) "reject hash mismatch"

  -- Wrong measurement
  let wrongM := { m with codeHash := Hash.sha256 "evil".toUTF8 }
  let wrongR := { r with measurement := wrongM }
  expect (!TeeReceipt.isAccept (TeeReceipt.acceptReceipt policy wrongR true)) "reject bad measurement"

  -- proofOk false
  expect (!TeeReceipt.isAccept (TeeReceipt.acceptReceipt policy r false)) "reject proofOk=false"

  -- Proto roundtrip
  let enc := Proto.TeeReceipt.encode r
  let dec ← IO.ofExcept (Proto.TeeReceipt.decode enc)
  expect (Hash.bytesEq dec.resultHash r.resultHash) "proto resultHash roundtrip"
  expect (Hash.bytesEq dec.publicIO.outputs r.publicIO.outputs) "proto outputs roundtrip"
  expect (TeeReceipt.isAccept (TeeReceipt.acceptReceipt policy dec true)) "decoded receipt accepts"

  -- Deny path still hashes consistently
  let denyIn := "action=transfer.funds\n".toUTF8
  let denyOut := Guest.runCompliance { rulesHash := cfgHash } denyIn
  expect ((Guest.inputsAsString denyOut).startsWith "decision=deny") "deny decision in outputs"

  -- Empty crypto_suite normalizes to sha256+mock and accepts
  let emptySuite := { r with receiptMeta := { r.receiptMeta with cryptoSuite := "" } }
  expect (TeeReceipt.isAccept (TeeReceipt.acceptReceipt policy emptySuite true))
    "empty suite ≡ sha256+mock"

  -- Fail-closed: Lean host rejects blake3+mock
  let blake := { r with receiptMeta := { r.receiptMeta with cryptoSuite := suiteBlake3Mock } }
  match TeeReceipt.acceptReceipt policy blake true with
  | .reject reason =>
    expect (reason.startsWith "unsupported crypto_suite=") "blake3 reject reason"
  | .accept => throw (IO.userError "blake3+mock must be rejected by Lean host")

  -- Fail-closed: unknown suite
  let unknown := { r with receiptMeta := { r.receiptMeta with cryptoSuite := "nope" } }
  expect (!TeeReceipt.isAccept (TeeReceipt.acceptReceipt policy unknown true))
    "unknown suite rejected"

  -- Proto preserves crypto_suite
  let withSuite := { r with receiptMeta := { r.receiptMeta with cryptoSuite := suiteSha256Mock } }
  let enc2 := Proto.TeeReceipt.encode withSuite
  let dec2 ← IO.ofExcept (Proto.TeeReceipt.decode enc2)
  expect (dec2.receiptMeta.cryptoSuite == suiteSha256Mock) "proto crypto_suite roundtrip"

  IO.println "receiptTests OK"
