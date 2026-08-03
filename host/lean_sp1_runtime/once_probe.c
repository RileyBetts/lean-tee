/*
 * SP1 bisect for lean_obj_once_cold. Stages committed as little-endian u32:
 *   1 = runtime init done
 *   2 = direct string_to_utf8 size
 *   3 = once_cold (stack tok) size
 *   4 = once_cold (static BSS tok) size
 *   5 = initialize_Hash then domainSeparator size
 */
#include <lean/lean.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

extern void lean_initialize_runtime_module(void);
extern lean_object *lean_string_to_utf8(lean_object *);
extern lean_object *initialize_lean_x2dtee_LeanTee_Hash(uint8_t builtin);
extern lean_object *lp_lean_x2dtee_LeanTee_Hash_domainSeparator;

static const lean_string_object g_str_value = {
    .m_header = {.m_rc = 0, .m_cs_sz = 0, .m_other = 0, .m_tag = 249},
    .m_size = 12,
    .m_capacity = 12,
    .m_length = 11,
    .m_data = "lean-tee/v1"};
static lean_object *const g_str = (lean_object *)&g_str_value;

static lean_object *init_utf8(void) { return lean_string_to_utf8(g_str); }

static lean_once_cell_t g_bss_once; /* BSS */
static lean_object *g_bss_loc;

/* Non-zero initializer → .data */
static lean_once_cell_t g_data_once = {.state = 2, .lock = 0};
static lean_object *g_data_loc;

uint32_t lean_tee_once_probe(uint32_t stage) {
  lean_initialize_runtime_module();
  if (stage <= 1)
    return 1;

  lean_object *direct = lean_string_to_utf8(g_str);
  lean_mark_persistent(direct);
  uint32_t direct_sz = (uint32_t)lean_sarray_size(direct);
  if (stage <= 2)
    return direct_sz; /* expect 11 */

  lean_once_cell_t stack_once = {.state = 0, .lock = 0};
  lean_object *stack_loc = NULL;
  lean_object *via_stack = lean_obj_once(&stack_loc, &stack_once, init_utf8);
  uint32_t stack_sz = (uint32_t)lean_sarray_size(via_stack);
  if (stage <= 3)
    return stack_sz; /* expect 11 */

  lean_object *via_bss = lean_obj_once(&g_bss_loc, &g_bss_once, init_utf8);
  uint32_t bss_sz = (uint32_t)lean_sarray_size(via_bss);
  if (stage <= 4)
    return bss_sz;

  lean_object *via_data = lean_obj_once(&g_data_loc, &g_data_once, init_utf8);
  (void)via_data;

  lean_object *res = initialize_lean_x2dtee_LeanTee_Hash(1);
  lean_dec_ref(res);
  uint32_t dom_sz = (uint32_t)lean_sarray_size(lp_lean_x2dtee_LeanTee_Hash_domainSeparator);
  return dom_sz;
}
