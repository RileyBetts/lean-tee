#!/usr/bin/env bash
# Emit/compile Init subset + GuestSp1 Lake C → .cache/lean-sp1-guest/libLeanTeeGuest.a
# Links against .cache/lean-sp1-runtime/prefix/lib/libLean.a at the SP1 guest link step.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.elan/bin:${HOME}/.sp1/riscv/bin:/usr/bin:/bin:${PATH:-}"

TC="${LEAN_TOOLCHAIN:-$HOME/.elan/toolchains/leanprover--lean4---v4.32.1}"
GCC="${CC_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/riscv/bin/riscv64-unknown-elf-gcc}"
AR="${AR_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/riscv/bin/riscv64-unknown-elf-ar}"
RT="${LEAN_SP1_RUNTIME_CACHE:-$ROOT/.cache/lean-sp1-runtime}"
PREFIX="$RT/prefix"
IR="$ROOT/.cache/lean-sp1-init/ir"
IOBJ="$ROOT/.cache/lean-sp1-init/obj"
GOBJ="$ROOT/.cache/lean-sp1-guest/obj"
OUT_A="$ROOT/.cache/lean-sp1-guest/libLeanTeeGuest.a"

test -x "$GCC" || { echo "missing SP1 gcc at $GCC (run: sp1up --c-toolchain)"; exit 1; }
test -f "$PREFIX/lib/libLean.a" || {
  echo "missing $PREFIX/lib/libLean.a — run scripts/sp1_lean_runtime_build.sh"
  exit 1
}

echo "== lake build GuestSp1 =="
lake build LeanTee.GuestSp1

echo "== emit Init subset C (toolchain oleans → l_* prefixes) =="
mkdir -p "$IR" "$IOBJ" "$GOBJ"
export LEAN_PATH="$TC/lib/lean"
MODS=(
  Init/Prelude.lean
  Init/Data/List/Basic.lean
  Init/Data/List/BasicAux.lean
  Init/GetElem.lean
  Init/Data/String/Legacy.lean
  Init/Util.lean
)
FORCE_EMIT="${SP1_LEAN_FORCE_EMIT:-0}"
for mod in "${MODS[@]}"; do
  base="$(basename "$mod" .lean)"
  dir="$(dirname "$mod")"
  mkdir -p "$IR/$dir"
  out="$IR/$dir/$base.c"
  if [[ "$FORCE_EMIT" == "1" || ! -f "$out" ]]; then
    echo "EMIT $mod"
    (cd "$TC/src/lean" && "$TC/bin/lean" "$mod" -c "$out")
  else
    echo "KEEP $out"
  fi
done

CFLAGS=(
  -O2 -fno-builtin -ffunction-sections -fdata-sections
  -march=rv64im -mabi=lp64 -DLEAN_SP1
  -I"$PREFIX/include"
  -I"$ROOT/host/lean_sp1_runtime/include"
  -I"$RT/lean4/src"
  -I"$RT/lean4/src/include"
)

echo "== compile Init + Guest C =="
for rel in Init/Prelude.c Init/Data/List/Basic.c Init/Data/List/BasicAux.c \
           Init/GetElem.c Init/Data/String/Legacy.c Init/Util.c; do
  base="$(basename "$rel" .c)"
  echo "CC $rel"
  "$GCC" "${CFLAGS[@]}" -c "$IR/$rel" -o "$IOBJ/$base.o"
done

"$GCC" "${CFLAGS[@]}" -c "$ROOT/host/lean_sp1_init_min/initialize_Init.c" -o "$IOBJ/initialize_Init.o"
"$GCC" "${CFLAGS[@]}" -c "$ROOT/host/lean_sp1_init_min/init_stubs.c" -o "$IOBJ/init_stubs.o"

for f in GuestSp1 GuestProg Guest Hash Measurement; do
  echo "CC LeanTee/$f.c"
  "$GCC" "${CFLAGS[@]}" -c "$ROOT/.lake/build/ir/LeanTee/$f.c" -o "$GOBJ/$f.o"
done
"$GCC" "${CFLAGS[@]}" -c "$ROOT/native/sha256_portable.c" -o "$GOBJ/sha256_portable.o"
"$GCC" "${CFLAGS[@]}" -c "$ROOT/host/lean_sp1_runtime/shims.c" -o "$GOBJ/shims.o"
"$GCC" "${CFLAGS[@]}" -c "$ROOT/host/lean_sp1_runtime/lean_guest_bridge.c" -o "$GOBJ/lean_guest_bridge.o"
"$GCC" "${CFLAGS[@]}" -c "$ROOT/host/lean_sp1_runtime/runtime_extern_stubs.c" -o "$GOBJ/runtime_extern_stubs.o"

echo "== archive $OUT_A =="
rm -f "$OUT_A"
"$AR" rcs "$OUT_A" \
  "$GOBJ"/GuestSp1.o "$GOBJ"/GuestProg.o "$GOBJ"/Guest.o "$GOBJ"/Hash.o "$GOBJ"/Measurement.o \
  "$GOBJ"/sha256_portable.o "$GOBJ"/shims.o "$GOBJ"/lean_guest_bridge.o \
  "$GOBJ"/runtime_extern_stubs.o \
  "$IOBJ"/initialize_Init.o "$IOBJ"/init_stubs.o \
  "$IOBJ"/Prelude.o "$IOBJ"/Basic.o "$IOBJ"/BasicAux.o \
  "$IOBJ"/GetElem.o "$IOBJ"/Legacy.o "$IOBJ"/Util.o

ls -lh "$OUT_A"
echo "sp1_lean_guest_build OK (link with $PREFIX/lib/libLean.a + libstdc++)"
