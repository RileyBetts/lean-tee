#include <lean/lean.h>
#include <stdint.h>

/* Defined in Init (Array/List/IO); not linked in the SP1 Init subset. */
LEAN_EXPORT lean_object *lean_list_to_array(lean_object *unit, lean_object *lst) {
  (void)unit;
  lean_dec(lst);
  return lean_alloc_array(0, 0);
}

LEAN_EXPORT lean_object *lean_array_to_list_impl(lean_object *unit, lean_object *arr) {
  (void)unit;
  lean_dec_ref(arr);
  return lean_box(0); /* List.nil */
}

LEAN_EXPORT lean_object *lean_io_eprintln(lean_object *s) {
  lean_dec_ref(s);
  return lean_io_result_mk_ok(lean_box(0));
}
