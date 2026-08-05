/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import LeanTee.Hash

namespace LeanTee

structure Measurement where
  codeHash : ByteArray
  configHash : ByteArray
  deriving Inhabited

namespace Measurement

def canonicalBytes (m : Measurement) : ByteArray :=
  Hash.concatLenPrefixed #[m.codeHash, m.configHash]

def digest (m : Measurement) : ByteArray :=
  Hash.sha256 m.canonicalBytes

def beq (a b : Measurement) : Bool :=
  Hash.bytesEq a.codeHash b.codeHash && Hash.bytesEq a.configHash b.configHash

end Measurement

/-- Allow-list of measured guest images (governance artifact). -/
structure MeasurementPolicy where
  allowed : Array Measurement
  deriving Inhabited

namespace MeasurementPolicy

def allows (p : MeasurementPolicy) (m : Measurement) : Bool :=
  p.allowed.any (Measurement.beq · m)

def singleton (m : Measurement) : MeasurementPolicy :=
  { allowed := #[m] }

end MeasurementPolicy

end LeanTee
