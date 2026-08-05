/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Hash
import LeanTee.Measurement

namespace LeanTee

/-- Registered CryptoSuite ids (see docs/CRYPTO.md). Empty meta ⇒ sha256+mock. -/
def suiteSha256Mock : String := "sha256+mock"
def suiteSha256Sp1 : String := "sha256+sp1"
def suiteBlake3Mock : String := "blake3+mock"

def normalizeCryptoSuite (s : String) : String :=
  if s.isEmpty then suiteSha256Mock else s

/-- Suites the Lean host can fully recompute. -/
def leanHostSupportsSuite (s : String) : Bool :=
  let n := normalizeCryptoSuite s
  n == suiteSha256Mock || n == suiteSha256Sp1

structure PublicIO where
  inputs : ByteArray
  outputs : ByteArray
  deriving Inhabited

structure ReceiptMeta where
  version : String
  domain : String
  sinkId : String
  cryptoSuite : String := ""
  /-- Empty = off; `local` = sealed-worker confidentiality (not hardware TEE). -/
  confidentiality : String := ""
  /-- Hex SHA-256 of secret_inputs when confidentiality=local. -/
  secretDigestHex : String := ""
  deriving Inhabited

def ReceiptMeta.default : ReceiptMeta :=
  { version := "v1", domain := "lean-tee/v1", sinkId := "", cryptoSuite := suiteSha256Mock }

structure TeeReceipt where
  measurement : Measurement
  publicIO : PublicIO
  resultHash : ByteArray
  nonce : ByteArray
  proofRef : ByteArray
  receiptMeta : ReceiptMeta
  deriving Inhabited

inductive ReceiptDecision where
  | accept
  | reject (reason : String)
  deriving BEq, Repr

namespace TeeReceipt

/--
`resultHash = SHA256(domain || measurement || inputs || outputs || nonce)`
with length-prefixed chunks. Lean host path is SHA-256 suites only.
-/
def computeResultHash (m : Measurement) (io : PublicIO) (nonce : ByteArray) : ByteArray :=
  let body := Hash.concatLenPrefixed #[
    Hash.domainSeparator,
    m.codeHash,
    m.configHash,
    io.inputs,
    io.outputs,
    nonce
  ]
  Hash.sha256 body

def withComputedHash (r : TeeReceipt) : TeeReceipt :=
  let rm :=
    if r.receiptMeta.cryptoSuite.isEmpty then
      { r.receiptMeta with cryptoSuite := suiteSha256Mock, domain := "lean-tee/v1" }
    else r.receiptMeta
  { r with
    receiptMeta := rm
    resultHash := computeResultHash r.measurement r.publicIO r.nonce }

def hashMatches (r : TeeReceipt) : Bool :=
  Hash.bytesEq r.resultHash (computeResultHash r.measurement r.publicIO r.nonce)

/-- Cheap accept/reject with suite fail-closed for Lean host. -/
def acceptReceipt (policy : MeasurementPolicy) (r : TeeReceipt) (proofOk : Bool) : ReceiptDecision :=
  let suite := normalizeCryptoSuite r.receiptMeta.cryptoSuite
  if !leanHostSupportsSuite suite then
    .reject s!"unsupported crypto_suite={suite} (Lean host; use lean_tee_receipt for blake3+mock)"
  else if !policy.allows r.measurement then
    .reject "measurement not in policy"
  else if !r.hashMatches then
    .reject "resultHash mismatch"
  else if !proofOk then
    .reject "proof invalid"
  else
    .accept

def isAccept : ReceiptDecision → Bool
  | .accept => true
  | .reject _ => false

end TeeReceipt

end LeanTee
