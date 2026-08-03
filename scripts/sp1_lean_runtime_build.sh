#!/usr/bin/env bash
# Attempt to compile Lean 4.32.1 runtime cores for SP1.
# Exit non-zero until LEAN_SP1 stubs land; prints a clear status summary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${LEAN_SP1_RUNTIME_CACHE:-$ROOT/.cache/lean-sp1-runtime}"
SRC="$CACHE/lean4"
BUILD="$CACHE/build"
PREFIX="$CACHE/prefix"

bash "$ROOT/scripts/sp1_lean_runtime_fetch.sh"

CXX="${CXX_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/riscv/bin/riscv64-unknown-elf-g++}"
AR="${AR_riscv64im_succinct_zkvm_elf:-$HOME/.sp1/riscv/bin/riscv64-unknown-elf-ar}"
test -x "$CXX" || { echo "missing SP1 g++ at $CXX (run: sp1up --c-toolchain)"; exit 1; }
test -x "$AR" || { echo "missing SP1 ar at $AR"; exit 1; }

rm -rf "$BUILD"
mkdir -p "$BUILD/obj" "$PREFIX/lib" "$PREFIX/include/lean"
cp -a "$HOME/.elan/toolchains/leanprover--lean4---v4.32.1/include/lean/." "$PREFIX/include/lean/"
# Prefer our SP1 config; drop toolchain version.h that redefines platform.
cp -f "$ROOT/host/lean_sp1_runtime/include/lean/config.h" "$PREFIX/include/lean/config.h"
rm -f "$PREFIX/include/lean/version.h"
cp -f "$ROOT/host/lean_sp1_runtime/include/lean/version.h" "$PREFIX/include/lean/version.h"
cp -f "$ROOT/host/lean_sp1_runtime/include/githash.h" "$PREFIX/include/githash.h"

# alloca for LEAN_ALLOCA on bare-metal RISC-V
ALLOCA_FLAGS=()
if [[ -f "$HOME/.sp1/riscv/riscv64-unknown-elf/include/alloca.h" ]] || \
   echo '#include <alloca.h>' | "$CXX" -x c - -fsyntax-only -march=rv64im -mabi=lp64 2>/dev/null; then
  ALLOCA_FLAGS+=(-include alloca.h)
fi

INC=(
  -I"$SRC/src"
  -I"$PREFIX/include"
  -I"$ROOT/host/lean_sp1_runtime/include"
)
# LEAN_SP1 is reserved for upcoming stubs (Anoma used LEAN_RISC0 on 4.22).
FLAGS=(
  -std=c++17 -O2 -DNDEBUG -DLEAN_EXPORTING -DLEAN_SP1=1
  -ffunction-sections -fdata-sections -fPIC
  -march=rv64im -mabi=lp64
  -fno-builtin -fno-exceptions -fno-rtti -fno-threadsafe-statics
  -Wall -Wno-unused-parameter -Wno-unused-function
  "${ALLOCA_FLAGS[@]}"
)

# Skip io/process/libuv/openssl/uv — too host-heavy for phase-1 guest.
CORE=(
  alloc.cpp object.cpp apply.cpp memory.cpp utf8.cpp hash.cpp
  init_module.cpp exception.cpp debug.cpp mpz.cpp mpn.cpp
  compact.cpp sharecommon.cpp interrupt.cpp platform.cpp
  stackinfo.cpp stack_overflow.cpp object_ref.cpp mutex.cpp
  thread.cpp allocprof.cpp
)
# Require patches applied by fetch script.
test -f "$SRC/.lean_sp1_patched" || {
  echo "missing LEAN_SP1 patches; run scripts/sp1_lean_runtime_fetch.sh"
  exit 1
}

OK=0
FAIL=0
OBJS=()
for f in "${CORE[@]}"; do
  src="$SRC/src/runtime/$f"
  base="${f%.cpp}"
  obj="$BUILD/obj/${base}.o"
  echo "CXX $base"
  if "$CXX" "${FLAGS[@]}" "${INC[@]}" -c "$src" -o "$obj" 2>"$BUILD/obj/${base}.err"; then
    OK=$((OK + 1))
    OBJS+=( "$obj" )
  else
    FAIL=$((FAIL + 1))
    echo "  FAILED (see $BUILD/obj/${base}.err)"
  fi
done

echo "runtime core compile: ok=$OK fail=$FAIL"
if (( FAIL != 0 )); then
  echo "LEAN_SP1 stubs still required (thread/IO/mmap/debug). See docs/LEAN_SP1_GUEST.md"
  head -n 20 "$BUILD"/obj/*.err 2>/dev/null | head -60 || true
  exit 1
fi

"$AR" rcs "$PREFIX/lib/libLean.a" "${OBJS[@]}"
echo "built $PREFIX/lib/libLean.a"
