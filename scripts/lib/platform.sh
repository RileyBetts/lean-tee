# Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
# SPDX-License-Identifier: Apache-2.0

# Portable helpers for Linux + macOS SP1 / host scripts.
# shellcheck shell=bash

# Print a short memory summary. Never fails under `set -e`.
print_mem_summary() {
  if command -v free >/dev/null 2>&1; then
    free -h | head -2 || true
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    local pages page_size free_p inactive_p avail_kib memsize
    page_size="$(pagesize 2>/dev/null || sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
    pages="$(vm_stat 2>/dev/null || true)"
    free_p="$(printf '%s\n' "$pages" | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')"
    inactive_p="$(printf '%s\n' "$pages" | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')"
    free_p="${free_p:-0}"
    inactive_p="${inactive_p:-0}"
    avail_kib=$(( (free_p + inactive_p) * page_size / 1024 ))
    memsize="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    echo "Darwin mem: hw.memsize=${memsize} approx_available_kib=${avail_kib} (free+inactive pages)"
  else
    echo "mem summary unavailable on $(uname -s)"
  fi
}

# Approximate available memory in KiB (nonempty integer).
# Linux: MemAvailable from /proc/meminfo.
# Darwin: (Pages free + Pages inactive) * pagesize / 1024.
mem_available_kib() {
  local kib
  if [[ -r /proc/meminfo ]]; then
    kib="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    if [[ -n "${kib:-}" ]]; then
      echo "$kib"
      return 0
    fi
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local page_size free_p inactive_p pages
    page_size="$(pagesize 2>/dev/null || sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
    pages="$(vm_stat 2>/dev/null || true)"
    free_p="$(printf '%s\n' "$pages" | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')"
    inactive_p="$(printf '%s\n' "$pages" | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')"
    free_p="${free_p:-0}"
    inactive_p="${inactive_p:-0}"
    echo $(( (free_p + inactive_p) * page_size / 1024 ))
    return 0
  fi
  echo 0
}

# Resolve a protoc binary: PATH first, else cargo vendored crate by OS/arch.
default_protoc() {
  if command -v protoc >/dev/null 2>&1; then
    command -v protoc
    return 0
  fi
  local os arch tag crate_dir
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) os=linux ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch_64 ;;
    *) arch=x86_64 ;;
  esac
  tag="${os}-${arch}"
  crate_dir="$(
    ls -d "${HOME}/.cargo/registry/src"/index.crates.io-*/protoc-bin-vendored-"${tag}"-* 2>/dev/null \
      | sort -V | tail -1 || true
  )"
  if [[ -n "${crate_dir}" && -x "${crate_dir}/bin/protoc" ]]; then
    echo "${crate_dir}/bin/protoc"
    return 0
  fi
  # Last resort: historical linux x86_64 pin (CI).
  echo "${HOME}/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/protoc-bin-vendored-linux-x86_64-3.2.0/bin/protoc"
}
