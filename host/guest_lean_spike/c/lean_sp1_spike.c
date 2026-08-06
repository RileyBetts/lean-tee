// AUTO-SYNCED skeleton from LeanTee/Sp1Spike.lean — phase-0 spike (no Init runtime).
// Regenerate commentary via: bash scripts/sp1_lean_spike_sync.sh
// The bodies of lean_tee_sp1_add / hello tag match Lake IR under Lean 4.32.1.
#include <stdint.h>

uint32_t lean_uint32_add(uint32_t a, uint32_t b) {
  return a + b;
}

uint32_t lean_tee_sp1_hello_tag = 1280528433u; /* 0x4C535031 'LSP1' */

uint32_t lean_tee_sp1_add(uint32_t a, uint32_t b) {
  return lean_uint32_add(a, b);
}
