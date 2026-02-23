#!/usr/bin/env bash
# Shared helpers for scripts/linux/*.sh

if [[ -n "${KATAGLYPHIS_LINUX_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
KATAGLYPHIS_LINUX_COMMON_SH_LOADED=1

init_repo_context() {
  local caller_source="${BASH_SOURCE[1]:-$0}"
  # shellcheck disable=SC2034
  SCRIPT_DIR="$(cd "$(dirname "${caller_source}")" && pwd)"
  # shellcheck disable=SC2034
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
  # shellcheck disable=SC2034
  WORKSPACE_ROOT="${WORKSPACE_ROOT:-${REPO_ROOT}}"

  cd "${REPO_ROOT}"
  git config --global --add safe.directory "${WORKSPACE_ROOT}" || true
}

append_clang_gcc_toolchain_args() {
  local compiler="${1:-}"
  local array_name="${2:-}"

  if [[ -z "${array_name}" ]]; then
    echo "append_clang_gcc_toolchain_args: missing array name" >&2
    return 1
  fi

  if [[ "${compiler}" == "clang" && -n "${CLANG_GCC_TOOLCHAIN:-}" ]]; then
    eval "${array_name}+=(\"-D\" \"CMAKE_C_FLAGS=--gcc-toolchain=${CLANG_GCC_TOOLCHAIN}\")"
    eval "${array_name}+=(\"-D\" \"CMAKE_CXX_FLAGS=--gcc-toolchain=${CLANG_GCC_TOOLCHAIN}\")"
  fi
}

append_default_toolchain_args() {
  local array_name="${1:-}"

  if [[ -z "${array_name}" ]]; then
    echo "append_default_toolchain_args: missing array name" >&2
    return 1
  fi

  if [[ -n "${CLANG_GCC_TOOLCHAIN:-}" ]]; then
    eval "${array_name}+=(\"-D\" \"CMAKE_C_FLAGS=--gcc-toolchain=${CLANG_GCC_TOOLCHAIN}\")"
    eval "${array_name}+=(\"-D\" \"CMAKE_CXX_FLAGS=--gcc-toolchain=${CLANG_GCC_TOOLCHAIN}\")"
  fi
}
