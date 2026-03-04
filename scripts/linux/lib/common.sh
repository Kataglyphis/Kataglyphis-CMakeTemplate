#!/usr/bin/env bash
# Shared helpers for scripts/linux/*.sh

if [[ -n "${KATAGLYPHIS_LINUX_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
KATAGLYPHIS_LINUX_COMMON_SH_LOADED=1

log_info() {
  printf "\n[INFO] %s\n" "$1"
}

log_warn() {
  printf "\n[WARN] %s\n" "$1"
}

require_cmd() {
  local cmd="$1"
  if [[ "${cmd}" == */* ]]; then
    if [[ ! -x "${cmd}" ]]; then
      echo "Missing required executable: ${cmd}" >&2
      return 1
    fi
    return 0
  fi

  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    return 1
  fi
}

ensure_uv_venv() {
  local venv_path="${1:-${REPO_ROOT}/.venv}"
  local requirements_path="${2:-${REPO_ROOT}/requirements.txt}"
  local activate_venv="${3:-false}"

  if [[ ! -d "${venv_path}" ]]; then
    require_cmd uv || return 1
    uv venv --allow-existing "${venv_path}"
  fi

  require_cmd uv || return 1
  uv pip install --python "${venv_path}/bin/python" -r "${requirements_path}"

  if [[ "${activate_venv}" == "true" ]]; then
    # shellcheck source=/dev/null
    source "${venv_path}/bin/activate"
  fi
}

cmake_configure_build() {
  local build_dir="$1"
  local preset="$2"
  shift 2

  cmake -B "${build_dir}" --preset "${preset}" "$@"
  cmake --build "${build_dir}" --preset "${preset}"
}

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
    eval "${array_name}+=(\"-D\" \"CMAKE_EXE_LINKER_FLAGS=--gcc-toolchain=${CLANG_GCC_TOOLCHAIN}\")"
    eval "${array_name}+=(\"-D\" \"CMAKE_SHARED_LINKER_FLAGS=--gcc-toolchain=${CLANG_GCC_TOOLCHAIN}\")"
    eval "${array_name}+=(\"-D\" \"GCC_TOOLCHAIN_PATH=${CLANG_GCC_TOOLCHAIN}\")"
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
    eval "${array_name}+=(\"-D\" \"GCC_TOOLCHAIN_PATH=${CLANG_GCC_TOOLCHAIN}\")"
  fi
}
