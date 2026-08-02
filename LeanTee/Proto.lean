/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Grpc
import Proto
import LeanTee.Measurement
import LeanTee.Receipt

/-! Protobuf codecs for `proto/lean_tee/v1/tee.proto` (hand-written; matches field tags). -/

namespace LeanTee.Proto
open LeanTee

def Measurement.encode (m : LeanTee.Measurement) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if !m.codeHash.isEmpty then acc := Proto.Wire.encodeBytes acc 1 m.codeHash
    if !m.configHash.isEmpty then acc := Proto.Wire.encodeBytes acc 2 m.configHash
    return acc

def Measurement.decode (b : ByteArray) : Except String LeanTee.Measurement := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return {
    codeHash := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
    configHash := (Proto.Wire.fieldBytes? fields 2).getD ByteArray.empty
  }

def PublicIO.encode (io : LeanTee.PublicIO) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if !io.inputs.isEmpty then acc := Proto.Wire.encodeBytes acc 1 io.inputs
    if !io.outputs.isEmpty then acc := Proto.Wire.encodeBytes acc 2 io.outputs
    return acc

def PublicIO.decode (b : ByteArray) : Except String LeanTee.PublicIO := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return {
    inputs := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
    outputs := (Proto.Wire.fieldBytes? fields 2).getD ByteArray.empty
  }

def ReceiptMeta.encode (m : LeanTee.ReceiptMeta) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if !m.version.isEmpty then acc := Proto.Wire.encodeString acc 1 m.version
    if !m.domain.isEmpty then acc := Proto.Wire.encodeString acc 2 m.domain
    if !m.sinkId.isEmpty then acc := Proto.Wire.encodeString acc 3 m.sinkId
    return acc

def ReceiptMeta.decode (b : ByteArray) : Except String LeanTee.ReceiptMeta := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return {
    version := (Proto.Wire.fieldString? fields 1).getD "v1"
    domain := (Proto.Wire.fieldString? fields 2).getD "lean-tee/v1"
    sinkId := (Proto.Wire.fieldString? fields 3).getD ""
  }

def TeeReceipt.encode (r : LeanTee.TeeReceipt) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    acc := Proto.Wire.encodeMessage acc 1 (Measurement.encode r.measurement)
    acc := Proto.Wire.encodeMessage acc 2 (PublicIO.encode r.publicIO)
    if !r.resultHash.isEmpty then acc := Proto.Wire.encodeBytes acc 3 r.resultHash
    if !r.nonce.isEmpty then acc := Proto.Wire.encodeBytes acc 4 r.nonce
    if !r.proofRef.isEmpty then acc := Proto.Wire.encodeBytes acc 5 r.proofRef
    acc := Proto.Wire.encodeMessage acc 6 (ReceiptMeta.encode r.receiptMeta)
    return acc

def TeeReceipt.decode (b : ByteArray) : Except String LeanTee.TeeReceipt := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  let mBytes := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
  let ioBytes := (Proto.Wire.fieldBytes? fields 2).getD ByteArray.empty
  let metaBytes := (Proto.Wire.fieldBytes? fields 6).getD ByteArray.empty
  let measurement ← Measurement.decode mBytes
  let publicIO ← PublicIO.decode ioBytes
  let receiptMeta ← ReceiptMeta.decode metaBytes
  return {
    measurement
    publicIO
    resultHash := (Proto.Wire.fieldBytes? fields 3).getD ByteArray.empty
    nonce := (Proto.Wire.fieldBytes? fields 4).getD ByteArray.empty
    proofRef := (Proto.Wire.fieldBytes? fields 5).getD ByteArray.empty
    receiptMeta
  }

structure ExecuteRequest where
  guestId : ByteArray := ByteArray.empty
  configHash : ByteArray := ByteArray.empty
  inputs : ByteArray := ByteArray.empty
  nonce : ByteArray := ByteArray.empty
  submitToSink : Bool := false
  deriving Inhabited

def ExecuteRequest.encode (m : ExecuteRequest) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if !m.guestId.isEmpty then acc := Proto.Wire.encodeBytes acc 1 m.guestId
    if !m.configHash.isEmpty then acc := Proto.Wire.encodeBytes acc 2 m.configHash
    if !m.inputs.isEmpty then acc := Proto.Wire.encodeBytes acc 3 m.inputs
    if !m.nonce.isEmpty then acc := Proto.Wire.encodeBytes acc 4 m.nonce
    if m.submitToSink then acc := Proto.Wire.encodeBool acc 5 true
    return acc

def ExecuteRequest.decode (b : ByteArray) : Except String ExecuteRequest := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return {
    guestId := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
    configHash := (Proto.Wire.fieldBytes? fields 2).getD ByteArray.empty
    inputs := (Proto.Wire.fieldBytes? fields 3).getD ByteArray.empty
    nonce := (Proto.Wire.fieldBytes? fields 4).getD ByteArray.empty
    submitToSink := ((Proto.Wire.fieldUInt32? fields 5).getD 0) != 0
  }

structure ExecuteResponse where
  jobId : String := ""
  receipt : Option LeanTee.TeeReceipt := none
  status : String := "pending"
  deriving Inhabited

def ExecuteResponse.encode (m : ExecuteResponse) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if !m.jobId.isEmpty then acc := Proto.Wire.encodeString acc 1 m.jobId
    match m.receipt with
    | some r => acc := Proto.Wire.encodeMessage acc 2 (TeeReceipt.encode r)
    | none => pure ()
    if !m.status.isEmpty then acc := Proto.Wire.encodeString acc 3 m.status
    return acc

def ExecuteResponse.decode (b : ByteArray) : Except String ExecuteResponse := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  let recBytes := Proto.Wire.fieldBytes? fields 2
  let receipt ← match recBytes with
    | none => pure none
    | some bb => TeeReceipt.decode bb >>= fun r => pure (some r)
  return {
    jobId := (Proto.Wire.fieldString? fields 1).getD ""
    receipt
    status := (Proto.Wire.fieldString? fields 3).getD "pending"
  }

structure GetReceiptRequest where
  jobId : String := ""
  deriving Inhabited

def GetReceiptRequest.encode (m : GetReceiptRequest) : ByteArray :=
  if m.jobId.isEmpty then ByteArray.empty
  else Proto.Wire.encodeString ByteArray.empty 1 m.jobId

def GetReceiptRequest.decode (b : ByteArray) : Except String GetReceiptRequest := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return { jobId := (Proto.Wire.fieldString? fields 1).getD "" }

structure MeasureRequest where
  configHash : ByteArray := ByteArray.empty
  deriving Inhabited

def MeasureRequest.encode (m : MeasureRequest) : ByteArray :=
  if m.configHash.isEmpty then ByteArray.empty
  else Proto.Wire.encodeBytes ByteArray.empty 1 m.configHash

def MeasureRequest.decode (b : ByteArray) : Except String MeasureRequest := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return { configHash := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty }

structure MeasureResponse where
  measurement : LeanTee.Measurement := { codeHash := ByteArray.empty, configHash := ByteArray.empty }
  deriving Inhabited

def MeasureResponse.encode (m : MeasureResponse) : ByteArray :=
  Proto.Wire.encodeMessage ByteArray.empty 1 (Measurement.encode m.measurement)

def MeasureResponse.decode (b : ByteArray) : Except String MeasureResponse := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  let mb := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
  let measurement ← Measurement.decode mb
  return { measurement }

structure ProveRequest where
  measurement : LeanTee.Measurement := { codeHash := ByteArray.empty, configHash := ByteArray.empty }
  inputs : ByteArray := ByteArray.empty
  deriving Inhabited

def ProveRequest.encode (m : ProveRequest) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    acc := Proto.Wire.encodeMessage acc 1 (Measurement.encode m.measurement)
    if !m.inputs.isEmpty then acc := Proto.Wire.encodeBytes acc 2 m.inputs
    return acc

def ProveRequest.decode (b : ByteArray) : Except String ProveRequest := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  let mb := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
  let measurement ← Measurement.decode mb
  return {
    measurement
    inputs := (Proto.Wire.fieldBytes? fields 2).getD ByteArray.empty
  }

structure ProveResponse where
  outputs : ByteArray := ByteArray.empty
  proofRef : ByteArray := ByteArray.empty
  deriving Inhabited

def ProveResponse.encode (m : ProveResponse) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if !m.outputs.isEmpty then acc := Proto.Wire.encodeBytes acc 1 m.outputs
    if !m.proofRef.isEmpty then acc := Proto.Wire.encodeBytes acc 2 m.proofRef
    return acc

def ProveResponse.decode (b : ByteArray) : Except String ProveResponse := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return {
    outputs := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
    proofRef := (Proto.Wire.fieldBytes? fields 2).getD ByteArray.empty
  }

structure AcceptReceiptRequest where
  receipt : LeanTee.TeeReceipt := default
  policyCodeHash : ByteArray := ByteArray.empty
  policyConfigHash : ByteArray := ByteArray.empty
  proofOk : Bool := false
  deriving Inhabited

def AcceptReceiptRequest.encode (m : AcceptReceiptRequest) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    acc := Proto.Wire.encodeMessage acc 1 (TeeReceipt.encode m.receipt)
    if !m.policyCodeHash.isEmpty then acc := Proto.Wire.encodeBytes acc 2 m.policyCodeHash
    if !m.policyConfigHash.isEmpty then acc := Proto.Wire.encodeBytes acc 3 m.policyConfigHash
    if m.proofOk then acc := Proto.Wire.encodeBool acc 4 true
    return acc

def AcceptReceiptRequest.decode (b : ByteArray) : Except String AcceptReceiptRequest := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  let rb := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
  let receipt ← TeeReceipt.decode rb
  return {
    receipt
    policyCodeHash := (Proto.Wire.fieldBytes? fields 2).getD ByteArray.empty
    policyConfigHash := (Proto.Wire.fieldBytes? fields 3).getD ByteArray.empty
    proofOk := ((Proto.Wire.fieldUInt32? fields 4).getD 0) != 0
  }

structure AcceptReceiptResponse where
  accepted : Bool := false
  reason : String := ""
  deriving Inhabited

def AcceptReceiptResponse.encode (m : AcceptReceiptResponse) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if m.accepted then acc := Proto.Wire.encodeBool acc 1 true
    if !m.reason.isEmpty then acc := Proto.Wire.encodeString acc 2 m.reason
    return acc

def AcceptReceiptResponse.decode (b : ByteArray) : Except String AcceptReceiptResponse := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return {
    accepted := ((Proto.Wire.fieldUInt32? fields 1).getD 0) != 0
    reason := (Proto.Wire.fieldString? fields 2).getD ""
  }

structure SubmitRequest where
  receipt : LeanTee.TeeReceipt := default
  deriving Inhabited

def SubmitRequest.encode (m : SubmitRequest) : ByteArray :=
  Proto.Wire.encodeMessage ByteArray.empty 1 (TeeReceipt.encode m.receipt)

def SubmitRequest.decode (b : ByteArray) : Except String SubmitRequest := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  let rb := (Proto.Wire.fieldBytes? fields 1).getD ByteArray.empty
  let receipt ← TeeReceipt.decode rb
  return { receipt }

structure SubmitAck where
  ok : Bool := false
  ref : String := ""
  message : String := ""
  deriving Inhabited

def SubmitAck.encode (m : SubmitAck) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    if m.ok then acc := Proto.Wire.encodeBool acc 1 true
    if !m.ref.isEmpty then acc := Proto.Wire.encodeString acc 2 m.ref
    if !m.message.isEmpty then acc := Proto.Wire.encodeString acc 3 m.message
    return acc

def SubmitAck.decode (b : ByteArray) : Except String SubmitAck := do
  let fields ← Proto.Wire.decodeFields (Bytes.Slice.ofByteArray b)
  return {
    ok := ((Proto.Wire.fieldUInt32? fields 1).getD 0) != 0
    ref := (Proto.Wire.fieldString? fields 2).getD ""
    message := (Proto.Wire.fieldString? fields 3).getD ""
  }

end LeanTee.Proto
