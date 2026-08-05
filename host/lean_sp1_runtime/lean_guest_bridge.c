/*
 * Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * Thin C bridge: host buffers ↔ Lean ByteArray ↔ lean_tee_guest_run.
 * Requires Lean runtime + Init + GuestSp1 objects linked into the SP1 guest.
 */
#include <lean/lean.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern lean_object *lean_tee_guest_run(lean_object *config_hash, lean_object *inputs,
                                       lean_object *program);
/* Lake package «lean-tee» → C prefix lean_x2dtee_ */
extern lean_object *initialize_lean_x2dtee_LeanTee_GuestSp1(uint8_t builtin);
extern void lean_initialize_runtime_module(void);

static lean_object *byte_array_from_c(const uint8_t *buf, size_t n) {
  lean_object *ba = lean_alloc_sarray(1, n, n);
  if (n > 0 && buf != NULL)
    memcpy(lean_sarray_cptr(ba), buf, n);
  return ba;
}

static int c_from_byte_array(lean_object *ba, uint8_t **out, size_t *out_n) {
  size_t n = lean_sarray_size(ba);
  uint8_t *dst = (uint8_t *)malloc(n == 0 ? 1 : n);
  if (!dst)
    return -1;
  if (n > 0)
    memcpy(dst, lean_sarray_cptr(ba), n);
  *out = dst;
  *out_n = n;
  return 0;
}

static int g_inited = 0;

static void ensure_lean_init(void) {
  if (g_inited)
    return;
  lean_initialize_runtime_module();
  lean_object *res = initialize_lean_x2dtee_LeanTee_GuestSp1(1 /* builtin */);
  lean_dec_ref(res);
  g_inited = 1;
}

/**
 * Run the Lean SP1 guest entry.
 * Caller frees *out_bytes with free().
 * Returns 0 on success, non-zero on allocation failure.
 */
int lean_tee_sp1_guest_run(const uint8_t *config_hash, size_t config_hash_len,
                           const uint8_t *inputs, size_t inputs_len, const uint8_t *program,
                           size_t program_len, uint8_t **out_bytes, size_t *out_len) {
  ensure_lean_init();
  lean_object *cfg = byte_array_from_c(config_hash, config_hash_len);
  lean_object *in = byte_array_from_c(inputs, inputs_len);
  lean_object *prog = byte_array_from_c(program, program_len);
  lean_object *out = lean_tee_guest_run(cfg, in, prog);
  int rc = c_from_byte_array(out, out_bytes, out_len);
  lean_dec_ref(out);
  return rc;
}
