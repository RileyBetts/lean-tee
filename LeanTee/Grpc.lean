/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Grpc
import LeanTee.Proto

namespace LeanTee.Grpc
open LeanTee.Proto

def teeService : String := "lean_tee.v1.Tee"
def proveService : String := "lean_tee.v1.Prove"
def verifyService : String := "lean_tee.v1.Verify"
def sinkService : String := "lean_tee.v1.AnchorSink"

structure TeeStub where
  channel : Grpc.Channel

namespace TeeStub

def Execute (self : TeeStub) (req : ExecuteRequest) : IO (Except String ExecuteResponse) := do
  let res ← Grpc.Channel.unary self.channel teeService "Execute" (ExecuteRequest.encode req)
  if res.status.code != .ok then return .error res.status.message
  return ExecuteResponse.decode res.message

def GetReceipt (self : TeeStub) (req : GetReceiptRequest) : IO (Except String ExecuteResponse) := do
  let res ← Grpc.Channel.unary self.channel teeService "GetReceipt" (GetReceiptRequest.encode req)
  if res.status.code != .ok then return .error res.status.message
  return ExecuteResponse.decode res.message

def Measure (self : TeeStub) (req : MeasureRequest) : IO (Except String MeasureResponse) := do
  let res ← Grpc.Channel.unary self.channel teeService "Measure" (MeasureRequest.encode req)
  if res.status.code != .ok then return .error res.status.message
  return MeasureResponse.decode res.message

end TeeStub

structure ProveStub where
  channel : Grpc.Channel

namespace ProveStub

def Prove (self : ProveStub) (req : ProveRequest) : IO (Except String ProveResponse) := do
  let res ← Grpc.Channel.unary self.channel proveService "Prove" (ProveRequest.encode req)
  if res.status.code != .ok then return .error res.status.message
  return ProveResponse.decode res.message

end ProveStub

structure VerifyStub where
  channel : Grpc.Channel

namespace VerifyStub

def AcceptReceipt (self : VerifyStub) (req : AcceptReceiptRequest) :
    IO (Except String AcceptReceiptResponse) := do
  let res ← Grpc.Channel.unary self.channel verifyService "AcceptReceipt"
    (AcceptReceiptRequest.encode req)
  if res.status.code != .ok then return .error res.status.message
  return AcceptReceiptResponse.decode res.message

end VerifyStub

structure AnchorSinkStub where
  channel : Grpc.Channel

namespace AnchorSinkStub

def Submit (self : AnchorSinkStub) (req : SubmitRequest) : IO (Except String SubmitAck) := do
  let res ← Grpc.Channel.unary self.channel sinkService "Submit" (SubmitRequest.encode req)
  if res.status.code != .ok then return .error res.status.message
  return SubmitAck.decode res.message

end AnchorSinkStub

def registerTeeExecute (s : Grpc.Server)
    (h : ExecuteRequest → IO (ExecuteResponse × Grpc.Status)) : Grpc.Server :=
  Grpc.Server.register s teeService "Execute" fun reqBytes => do
    match ExecuteRequest.decode reqBytes with
    | .error e => return (ByteArray.empty, Grpc.Status.invalidArgument e)
    | .ok req =>
      let (resp, st) ← h req
      return (ExecuteResponse.encode resp, st)

def registerTeeGetReceipt (s : Grpc.Server)
    (h : GetReceiptRequest → IO (ExecuteResponse × Grpc.Status)) : Grpc.Server :=
  Grpc.Server.register s teeService "GetReceipt" fun reqBytes => do
    match GetReceiptRequest.decode reqBytes with
    | .error e => return (ByteArray.empty, Grpc.Status.invalidArgument e)
    | .ok req =>
      let (resp, st) ← h req
      return (ExecuteResponse.encode resp, st)

def registerTeeMeasure (s : Grpc.Server)
    (h : MeasureRequest → IO (MeasureResponse × Grpc.Status)) : Grpc.Server :=
  Grpc.Server.register s teeService "Measure" fun reqBytes => do
    match MeasureRequest.decode reqBytes with
    | .error e => return (ByteArray.empty, Grpc.Status.invalidArgument e)
    | .ok req =>
      let (resp, st) ← h req
      return (MeasureResponse.encode resp, st)

def registerProve (s : Grpc.Server)
    (h : ProveRequest → IO (ProveResponse × Grpc.Status)) : Grpc.Server :=
  Grpc.Server.register s proveService "Prove" fun reqBytes => do
    match ProveRequest.decode reqBytes with
    | .error e => return (ByteArray.empty, Grpc.Status.invalidArgument e)
    | .ok req =>
      let (resp, st) ← h req
      return (ProveResponse.encode resp, st)

def registerVerifyAccept (s : Grpc.Server)
    (h : AcceptReceiptRequest → IO (AcceptReceiptResponse × Grpc.Status)) : Grpc.Server :=
  Grpc.Server.register s verifyService "AcceptReceipt" fun reqBytes => do
    match AcceptReceiptRequest.decode reqBytes with
    | .error e => return (ByteArray.empty, Grpc.Status.invalidArgument e)
    | .ok req =>
      let (resp, st) ← h req
      return (AcceptReceiptResponse.encode resp, st)

def registerAnchorSinkSubmit (s : Grpc.Server)
    (h : SubmitRequest → IO (SubmitAck × Grpc.Status)) : Grpc.Server :=
  Grpc.Server.register s sinkService "Submit" fun reqBytes => do
    match SubmitRequest.decode reqBytes with
    | .error e => return (ByteArray.empty, Grpc.Status.invalidArgument e)
    | .ok req =>
      let (resp, st) ← h req
      return (SubmitAck.encode resp, st)

end LeanTee.Grpc
