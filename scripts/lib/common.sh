# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Shared helpers for lean-tee demo scripts. Source from repo scripts/*.sh
# shellcheck shell=bash

demo_root() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  export ROOT
  cd "$ROOT"
  # Mock demos: do not require SP1 prove_server (production default is lean-tee-v2).
  export LEAN_TEE_DEFAULT_PROFILE="${LEAN_TEE_DEFAULT_PROFILE:-lean-tee-v1}"
}

require_lean_grpc() {
  if [[ -d "$ROOT/.lake/packages/lean-grpc" || -d "$ROOT/../lean-grpc" ]]; then
    return 0
  fi
  if command -v lake >/dev/null 2>&1; then
    echo "fetching lean-grpc via lake update…" >&2
    (cd "$ROOT" && lake update)
    return 0
  fi
  echo "missing lean-grpc; run: lake update  (or clone ../lean-grpc @ v1.0.0)" >&2
  exit 1
}

export_pythonpath() {
  export PYTHONPATH="$ROOT/clients/python${PYTHONPATH:+:$PYTHONPATH}"
}

wait_port() {
  local host="$1" port="$2" n="${3:-40}"
  for _ in $(seq 1 "$n"); do
    if command -v nc >/dev/null 2>&1; then
      if nc -z "$host" "$port" >/dev/null 2>&1; then
        return 0
      fi
    elif (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.15
  done
  # last resort: short sleep after spawn
  sleep 0.5
  return 0
}
