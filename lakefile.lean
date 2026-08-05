/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
import Lake
open Lake DSL
open System

package «lean-tee» where
  version := v!"1.0.0"
  keywords := #["tee", "zkvm", "grpc", "compliance", "attestation"]
  description := "Lean-specified zkTEE: measured guest execution, hashed receipts, lean-grpc APIs"
  license := "Apache-2.0"
  licenseFiles := #["LICENSE", "NOTICE"]

/-- Pinned for CI, docs, and [Reservoir](https://reservoir.lean-lang.org/) reproducible builds. -/
require «lean-grpc» from git
  "https://github.com/RileyBetts/lean-grpc.git" @ "v1.0.0"

target sha256_ffi.o pkg : FilePath := do
  let oFile := pkg.buildDir / "native" / "sha256_ffi.o"
  let srcJob ← inputTextFile <| pkg.dir / "native" / "sha256_ffi.c"
  let leanInc ← getLeanIncludeDir
  let mut incArgs : Array String := #["-fPIC", "-O2", "-I", leanInc.toString]
  let opensslCflags ← IO.Process.output { cmd := "pkg-config", args := #["--cflags", "openssl"] }
  if opensslCflags.exitCode == 0 then
    let cleaned := String.ofList <| opensslCflags.stdout.toList.map fun c =>
      if c.isWhitespace then ' ' else c
    for a in (cleaned.splitOn " ").filter (· ≠ "") do
      incArgs := incArgs.push a
  else
    let siblingInc := pkg.dir / ".." / "lean-grpc" / ".lake" / "deps" / "openssl-3.0.13" / "include"
    let vendoredInc := pkg.dir / ".lake" / "deps" / "openssl-3.0.13" / "include"
    if ← siblingInc.pathExists then
      incArgs := incArgs.push "-I" |>.push siblingInc.toString
    else if ← vendoredInc.pathExists then
      incArgs := incArgs.push "-I" |>.push vendoredInc.toString
  buildO oFile srcJob #[] incArgs

@[default_target]
lean_lib LeanTee where
  moreLinkObjs := #[sha256_ffi.o]
  moreLinkArgs := #["-lssl", "-lcrypto"]

lean_exe receiptTests where
  root := `Tests.ReceiptMain

lean_exe teeLoopback where
  root := `Tests.TeeLoopback

lean_exe teeServer where
  root := `LeanTee.ServerMain

lean_exe teeClient where
  root := `LeanTee.ExecuteClientMain

lean_exe proveMockServer where
  root := `LeanTee.ProveMockMain

lean_exe rustProveLoopback where
  root := `Tests.RustProveLoopback

lean_exe goldenVectors where
  root := `Tests.GoldenVectors

lean_exe adversarialMatrix where
  root := `Tests.AdversarialMatrix

lean_exe guestRegistry where
  root := `Tests.GuestRegistry

lean_exe guestProgTests where
  root := `Tests.GuestProgMain

lean_exe guestProgClient where
  root := `LeanTee.GuestProgClientMain

lean_exe confidentialClient where
  root := `LeanTee.ConfidentialClientMain
