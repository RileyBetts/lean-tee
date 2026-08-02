/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace LeanTee.Hash

/-- SHA-256 via OpenSSL (`native/sha256_ffi.c`). Returns 32 bytes, or empty on failure. -/
@[extern "lean_tee_sha256"]
opaque sha256 : ByteArray → ByteArray

def bytesEq (a b : ByteArray) : Bool :=
  a.size == b.size && Id.run do
    let mut i := 0
    while i < a.size do
      if a.get! i != b.get! i then return false
      i := i + 1
    pure true

/-- Length-delimited concatenation: `u32be(len) || bytes` per chunk. -/
def concatLenPrefixed (chunks : Array ByteArray) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    for c in chunks do
      let n := c.size.toUInt32
      acc := acc.push (n >>> 24).toUInt8
      acc := acc.push (n >>> 16).toUInt8
      acc := acc.push (n >>> 8).toUInt8
      acc := acc.push n.toUInt8
      acc := acc ++ c
    return acc

def domainSeparator : ByteArray := "lean-tee/v1".toUTF8

private def hexVal (c : Char) : Option UInt8 :=
  let n := c.toNat
  if '0'.toNat ≤ n ∧ n ≤ '9'.toNat then some (n - '0'.toNat).toUInt8
  else if 'a'.toNat ≤ n ∧ n ≤ 'f'.toNat then some (n - 'a'.toNat + 10).toUInt8
  else if 'A'.toNat ≤ n ∧ n ≤ 'F'.toNat then some (n - 'A'.toNat + 10).toUInt8
  else none

/-- Decode lowercase/uppercase hex into bytes; `none` on odd length or bad digits. -/
def hexDecode? (s : String) : Option ByteArray :=
  if s.length % 2 != 0 then none
  else Id.run do
    let mut out := ByteArray.empty
    let mut i := 0
    while i + 1 < s.length do
      match hexVal (s.get! ⟨i⟩), hexVal (s.get! ⟨i + 1⟩) with
      | some hi, some lo =>
        out := out.push (hi * 16 + lo)
        i := i + 2
      | _, _ => return none
    return some out

end LeanTee.Hash