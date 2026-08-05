# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Shared helpers for lean-tee demo scripts. Source from repo scripts/*.sh
# shellcheck shell=bash

demo_root() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  export ROOT
  cd "$ROOT"
}

require_lean_grpc() {
  if [[ ! -d "$ROOT/../lean-grpc" ]]; then
    echo "missing sibling ../lean-grpc (pin v1.0.0)" >&2
    exit 1
  fi
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
