/-
Copyright (c) 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import LeanTee.Hash
import LeanTee.Measurement

namespace LeanTee

structure PublicIO where
  inputs : ByteArray
  outputs : ByteArray
  deriving Inhabited

structure ReceiptMeta where
  version : String
  domain : String
  sinkId : String
  deriving Inhabited

def ReceiptMeta.default : ReceiptMeta :=
  { version := "v1", domain := "lean-tee/v1", sinkId := "" }

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
with length-prefixed chunks.
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
  { r with resultHash := computeResultHash r.measurement r.publicIO r.nonce }

def hashMatches (r : TeeReceipt) : Bool :=
  Hash.bytesEq r.resultHash (computeResultHash r.measurement r.publicIO r.nonce)

/-- Cheap accept/reject: measurement policy + resultHash binding + external proofOk. -/
def acceptReceipt (policy : MeasurementPolicy) (r : TeeReceipt) (proofOk : Bool) : ReceiptDecision :=
  if !policy.allows r.measurement then
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
