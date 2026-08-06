/-
Copyright © 2026, Riley Betts Ltd (rileybetts.ai)
SPDX-License-Identifier: Apache-2.0
-/
/-!
# SP1 Lean mid guest (between spike and full compliance)

Still **Init-free**: pure `UInt32` exports only. Richer than [`Sp1Spike`](Sp1Spike.lean)
(mix + fixed rounds), lighter than the measured compliance ELF (no Lean runtime).

Intended for laptop CPU prove+verify.
-/

namespace LeanTee.Sp1Mid

/-- Mid-tier tag (`MID1`). -/
@[export lean_tee_sp1_mid_tag]
def midTag : UInt32 := 0x4d494431

/-- One mix step (LCG-style; Init-free). -/
@[export lean_tee_sp1_mid_step]
def step (acc x : UInt32) : UInt32 :=
  let y := acc ^^^ x
  y * 1664525 + 1013904223

/-- Apply `step` with `x = 0 .. n-1` starting from `seed`. -/
@[export lean_tee_sp1_mid_rounds]
def rounds (seed n : UInt32) : UInt32 :=
  Id.run do
    let mut a := seed
    for i in [0:n.toNat] do
      a := step a (UInt32.ofNat i)
    pure a

end LeanTee.Sp1Mid
