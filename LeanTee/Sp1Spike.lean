/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
Released under Apache 2.0 license as described in the file LICENSE.
-/
/-!
# SP1 Lean guest spike (phase 0)

Pure entry with no IO. Phase 0 proves Lean→C can be linked into the SP1 guest.
Semantic operators (compliance / GuestProg) land in later phases.
-/

namespace LeanTee.Sp1Spike

/-- Phase-0 hello: deterministic tag bytes (no heap-heavy ByteArray API in the export). -/
@[export lean_tee_sp1_hello_tag]
def helloTag : UInt32 := 0x4c535031  -- 'LSP1'

/-- Phase-0 pure arithmetic (minimal C; mirrors Anoma sum-example style). -/
@[export lean_tee_sp1_add]
def add (a b : UInt32) : UInt32 := a + b

end LeanTee.Sp1Spike
