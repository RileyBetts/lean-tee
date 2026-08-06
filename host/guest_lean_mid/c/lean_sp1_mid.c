// AUTO-SYNCED skeleton from LeanTee/Sp1Mid.lean — mid-tier spike (no Init runtime).
// Regenerate commentary via: bash scripts/sp1_lean_mid_sync.sh
#include <stdint.h>

uint32_t lean_tee_sp1_mid_tag = 1296647217u; /* 0x4D494431 'MID1' */

uint32_t lean_tee_sp1_mid_step(uint32_t acc, uint32_t x) {
  uint32_t y = acc ^ x;
  return y * 1664525u + 1013904223u;
}

uint32_t lean_tee_sp1_mid_rounds(uint32_t seed, uint32_t n) {
  uint32_t a = seed;
  for (uint32_t i = 0; i < n; i++) {
    a = lean_tee_sp1_mid_step(a, i);
  }
  return a;
}
