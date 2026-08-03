#!/usr/bin/env bash
# Fetch Lean 4.32.1 runtime sources (sparse) for SP1 porting.
# Anoma's lean-risc0-runtime targets Lean 4.22 and does not match 4.32.1 headers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${LEAN_SP1_RUNTIME_CACHE:-$ROOT/.cache/lean-sp1-runtime}"
SRC="$CACHE/lean4"
LEAN_TAG="${LEAN_SP1_LEAN_TAG:-v4.32.1}"
REPO_URL="${LEAN4_GIT:-https://github.com/leanprover/lean4.git}"

mkdir -p "$CACHE"
if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  git clone --depth 1 --branch "$LEAN_TAG" --filter=blob:none --sparse "$REPO_URL" "$SRC"
  git -C "$SRC" sparse-checkout set src/runtime src/include
else
  git -C "$SRC" fetch --depth 1 origin "refs/tags/$LEAN_TAG:refs/tags/$LEAN_TAG" || true
  git -C "$SRC" checkout "$LEAN_TAG"
  git -C "$SRC" sparse-checkout set src/runtime src/include
fi

mkdir -p "$SRC/src/include/lean"
cp -f "$ROOT/host/lean_sp1_runtime/include/lean/config.h" "$SRC/src/include/lean/config.h"
cp -f "$ROOT/host/lean_sp1_runtime/include/lean/version.h" "$SRC/src/include/lean/version.h"
cp -f "$ROOT/host/lean_sp1_runtime/include/githash.h" "$SRC/src/include/githash.h"

cat >"$CACHE/PROVENANCE.txt" <<EOF
source=$REPO_URL@$LEAN_TAG
overlay=$ROOT/host/lean_sp1_runtime
fetched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
note=Stock Lean runtime needs LEAN_SP1 stubs (threads/IO/mmap) before SP1 link succeeds.
EOF

echo "fetched Lean $LEAN_TAG runtime → $SRC"
