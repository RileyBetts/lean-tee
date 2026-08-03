#include <lean/lean.h>
#include <stdint.h>

#define STUB_INIT(name)                                                                                \
  LEAN_EXPORT lean_object *name(uint8_t builtin) {                                                     \
    (void)builtin;                                                                                     \
    return lean_io_result_mk_ok(lean_box(0));                                                          \
  }

/* Transitive Init module inits referenced by compiled Init IR wrappers we still link. */
STUB_INIT(initialize_Init_ByCases)
STUB_INIT(initialize_Init_Classical)
STUB_INIT(initialize_Init_Data_Array_Basic)
STUB_INIT(initialize_Init_Data_List_Notation)
STUB_INIT(initialize_Init_Data_Nat_Basic)
STUB_INIT(initialize_Init_Data_Nat_Linear)
STUB_INIT(initialize_Init_Data_Option_Basic)
STUB_INIT(initialize_Init_Data_String_Basic)
STUB_INIT(initialize_Init_Data_ToString_Basic)
STUB_INIT(initialize_Init_Data_Zero)
STUB_INIT(initialize_Init_Grind_Tactics)
STUB_INIT(initialize_Init_SimpLemmas)
STUB_INIT(initialize_Init_WFTactics)

STUB_INIT(runtime_initialize_Init_ByCases)
STUB_INIT(runtime_initialize_Init_Classical)
STUB_INIT(runtime_initialize_Init_Data_Array_Basic)
STUB_INIT(runtime_initialize_Init_Data_List_Notation)
STUB_INIT(runtime_initialize_Init_Data_Nat_Basic)
STUB_INIT(runtime_initialize_Init_Data_Nat_Linear)
STUB_INIT(runtime_initialize_Init_Data_Option_Basic)
STUB_INIT(runtime_initialize_Init_Data_String_Basic)
STUB_INIT(runtime_initialize_Init_Data_ToString_Basic)
STUB_INIT(runtime_initialize_Init_Data_Zero)
STUB_INIT(runtime_initialize_Init_Grind_Tactics)
STUB_INIT(runtime_initialize_Init_SimpLemmas)
STUB_INIT(runtime_initialize_Init_WFTactics)

/* Used only on the List.get! panic path. */
LEAN_EXPORT lean_object *l_Nat_reprFast(lean_object *n) {
  (void)n;
  return lean_mk_string("nat");
}
