#include <lean/lean.h>
#include <stdint.h>

extern lean_object *l_ByteArray_empty;

/*
 * Guest modules call initialize_Init. Full `runtime_initialize_Init_Prelude`
 * crashes under SP1 (panic → unimp). Only ByteArray.empty is required as a
 * closed value for the compliance slice; List/String helpers are pure.
 */
LEAN_EXPORT lean_object *initialize_Init(uint8_t builtin) {
  static uint8_t once = 0;
  if (once)
    return lean_io_result_mk_ok(lean_box(0));
  once = 1;
  (void)builtin;
  lean_object *z = lean_unsigned_to_nat(0u);
  l_ByteArray_empty = lean_mk_empty_byte_array(z);
  lean_dec(z);
  lean_mark_persistent(l_ByteArray_empty);
  return lean_io_result_mk_ok(lean_box(0));
}
