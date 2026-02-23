#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SELF_DIR}/lib/common.sh"
init_repo_context

FORMAT_MODE="fix"
CONFIGURE_PRESET="linux-debug-clang"
COMPILE_DB=""
INCLUDE_FUZZ_PERF="false"
TIDY_FIX_MODE="false"

log_info() {
  printf "\n[INFO] %s\n" "$1"
}

log_warn() {
  printf "\n[WARN] %s\n" "$1"
}

ensure_tooling_environment() {
  if command -v clang-format >/dev/null 2>&1 && command -v cmake-format >/dev/null 2>&1; then
    return 0
  fi

  log_warn "clang-format or cmake-format not found. Trying to activate .venv"

  if [[ ! -d "${REPO_ROOT}/.venv" ]]; then
    log_info ".venv not found. Creating with uv and installing requirements.txt"
    if ! command -v uv >/dev/null 2>&1; then
      echo "Error: uv not found and .venv does not exist. Install uv first."
      exit 1
    fi

    uv venv "${REPO_ROOT}/.venv"
    uv pip install --python "${REPO_ROOT}/.venv/bin/python" -r "${REPO_ROOT}/requirements.txt"
  fi

  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.venv/bin/activate"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Runs clang-format, cmake-format and clang-tidy over project sources.

Options:
  --check-format            Run clang-format in check mode (no changes)
  --fix-format              Run clang-format in fix mode (default)
  --configure-preset NAME   CMake configure preset to generate compile_commands.json
                            (default: ${CONFIGURE_PRESET})
  --compile-db PATH         Path to compile_commands.json or its directory
  --include-fuzz-perf       Also run clang-tidy for Test/fuzz and Test/perf files
  --fix-tidy                Apply clang-tidy fixes (--fix --fix-errors)
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-format)
      FORMAT_MODE="check"
      shift
      ;;
    --fix-format)
      FORMAT_MODE="fix"
      shift
      ;;
    --configure-preset)
      [[ $# -ge 2 ]] || { echo "Missing value for --configure-preset"; exit 1; }
      CONFIGURE_PRESET="$2"
      shift 2
      ;;
    --compile-db)
      [[ $# -ge 2 ]] || { echo "Missing value for --compile-db"; exit 1; }
      COMPILE_DB="$2"
      shift 2
      ;;
    --include-fuzz-perf)
      INCLUDE_FUZZ_PERF="true"
      shift
      ;;
    --fix-tidy)
      TIDY_FIX_MODE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

ensure_tooling_environment

for tool in clang-format clang-tidy cmake cmake-format; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool not found: $tool"
    exit 1
  fi
done

mapfile -t CLANG_FORMAT_FILES < <(
  find "${REPO_ROOT}/Src" "${REPO_ROOT}/Test" \
    -type f \( -name "*.c" -o -name "*.cc" -o -name "*.cpp" -o -name "*.cxx" -o -name "*.h" -o -name "*.hh" -o -name "*.hpp" -o -name "*.hxx" -o -name "*.inl" \) \
    | grep -Ev '/ExternalLib/' \
    | sort
)

mapfile -t CMAKE_FORMAT_FILES < <(
  {
    find "${REPO_ROOT}" -maxdepth 1 -type f -name "CMakeLists.txt"
    find "${REPO_ROOT}/cmake" "${REPO_ROOT}/Src" "${REPO_ROOT}/Test" \
      -type f \( -name "CMakeLists.txt" -o -name "*.cmake" \)
  } \
    | grep -Ev '/ExternalLib/' \
    | sort -u
)

if [[ ${#CLANG_FORMAT_FILES[@]} -eq 0 && ${#CMAKE_FORMAT_FILES[@]} -eq 0 ]]; then
  log_warn "No files found for clang-format or cmake-format."
  exit 0
fi

mapfile -t TIDY_FILES < <(
  printf '%s\n' "${CLANG_FORMAT_FILES[@]}" | grep -E '\.(c|cc|cpp|cxx)$' || true
)

if [[ "${INCLUDE_FUZZ_PERF}" != "true" ]]; then
  mapfile -t TIDY_FILES < <(
    printf '%s\n' "${TIDY_FILES[@]}" | grep -Ev '/Test/(fuzz|perf)/' || true
  )
fi

log_info "Running clang-format (${FORMAT_MODE}) on ${#CLANG_FORMAT_FILES[@]} files"
FORMAT_FAIL=0
for file in "${CLANG_FORMAT_FILES[@]}"; do
  if [[ "$FORMAT_MODE" == "fix" ]]; then
    clang-format -i "$file"
  else
    if ! clang-format --dry-run --Werror "$file"; then
      echo "clang-format check failed: $file"
      FORMAT_FAIL=1
    fi
  fi
done

log_info "Running cmake-format (fix) on ${#CMAKE_FORMAT_FILES[@]} files"
CMAKE_FORMAT_FAIL=0
for file in "${CMAKE_FORMAT_FILES[@]}"; do
  if ! cmake-format --in-place "$file"; then
    echo "cmake-format failed: $file"
    CMAKE_FORMAT_FAIL=1
  fi
done

resolve_compile_db_dir() {
  local input_path="$1"

  if [[ -z "$input_path" ]]; then
    return 1
  fi

  if [[ -f "$input_path" ]]; then
    dirname "$input_path"
    return 0
  fi

  if [[ -f "$input_path/compile_commands.json" ]]; then
    echo "$input_path"
    return 0
  fi

  return 1
}

if ! COMPILE_DB_DIR="$(resolve_compile_db_dir "$COMPILE_DB")"; then
  for candidate in "${REPO_ROOT}/build" "${REPO_ROOT}/build-release"; do
    if [[ -f "$candidate/compile_commands.json" ]]; then
      COMPILE_DB_DIR="$candidate"
      break
    fi
  done
fi

if [[ -z "${COMPILE_DB_DIR:-}" ]]; then
  log_info "compile_commands.json not found. Generating with preset: ${CONFIGURE_PRESET}"
  cmake --preset "${CONFIGURE_PRESET}" -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  if [[ -f "${REPO_ROOT}/build/compile_commands.json" ]]; then
    COMPILE_DB_DIR="${REPO_ROOT}/build"
  elif [[ -f "${REPO_ROOT}/build-release/compile_commands.json" ]]; then
    COMPILE_DB_DIR="${REPO_ROOT}/build-release"
  else
    echo "Error: compile_commands.json could not be generated."
    exit 1
  fi
fi

log_info "Using compile database: ${COMPILE_DB_DIR}/compile_commands.json"

if [[ ${#TIDY_FILES[@]} -eq 0 ]]; then
  log_warn "No C/C++ translation units found for clang-tidy."
else
  log_info "Running clang-tidy on ${#TIDY_FILES[@]} files"
fi

TIDY_FAIL=0
for file in "${TIDY_FILES[@]}"; do
  TIDY_ARGS=(
    "$file"
    -p "$COMPILE_DB_DIR"
    --quiet
    --header-filter="^${REPO_ROOT}/(Src|Test)/"
  )

  if [[ "${TIDY_FIX_MODE}" == "true" ]]; then
    TIDY_ARGS+=(--fix --fix-errors)
  fi

  if ! clang-tidy "${TIDY_ARGS[@]}"; then
    echo "clang-tidy failed: $file"
    TIDY_FAIL=1
  fi
done

if [[ "${TIDY_FIX_MODE}" == "true" ]]; then
  log_info "Running clang-format after clang-tidy fixes"
  for file in "${CLANG_FORMAT_FILES[@]}"; do
    clang-format -i "$file"
  done

  log_info "Running cmake-format after clang-tidy fixes"
  for file in "${CMAKE_FORMAT_FILES[@]}"; do
    cmake-format --in-place "$file"
  done
fi

if [[ "$FORMAT_MODE" == "check" && "$FORMAT_FAIL" -ne 0 ]]; then
  echo "clang-format check failed for one or more files."
fi
if [[ "$CMAKE_FORMAT_FAIL" -ne 0 ]]; then
  echo "cmake-format failed for one or more files."
fi
if [[ "$TIDY_FAIL" -ne 0 ]]; then
  echo "clang-tidy failed for one or more files."
fi

if [[ "$FORMAT_MODE" == "check" && "$FORMAT_FAIL" -ne 0 ]] || [[ "$CMAKE_FORMAT_FAIL" -ne 0 ]] || [[ "$TIDY_FAIL" -ne 0 ]]; then
  exit 1
fi

log_info "clang-format, cmake-format and clang-tidy completed successfully"
