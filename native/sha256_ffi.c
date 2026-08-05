/*
 * Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
 * SPDX-License-Identifier: Apache-2.0
 */

#include <lean/lean.h>
#include <openssl/evp.h>
#include <stdint.h>
#include <string.h>

static lean_obj_res mk_byte_array_copy(const uint8_t *data, size_t len) {
  lean_obj_res arr = lean_alloc_sarray(1, len, len);
  if (len > 0 && data != NULL)
    memcpy(lean_sarray_cptr(arr), data, len);
  return arr;
}

lean_obj_res lean_tee_sha256(b_lean_obj_arg input) {
  size_t n = lean_sarray_size(input);
  const uint8_t *data = lean_sarray_cptr(input);
  uint8_t out[32];
  unsigned int out_len = 0;
  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  if (ctx == NULL)
    return mk_byte_array_copy(NULL, 0);
  int ok = EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) == 1
        && EVP_DigestUpdate(ctx, data, n) == 1
        && EVP_DigestFinal_ex(ctx, out, &out_len) == 1
        && out_len == 32;
  EVP_MD_CTX_free(ctx);
  if (!ok)
    return mk_byte_array_copy(NULL, 0);
  return mk_byte_array_copy(out, 32);
}
