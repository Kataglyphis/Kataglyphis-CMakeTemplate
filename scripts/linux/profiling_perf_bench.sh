#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

git config --global --add safe.directory /workspace || true

MATRIX_COMPILER="clang"
BUILD_DIR="build"
GCC_PROFILE_PRESET="linux-profile-GNU"
CLANG_PROFILE_PRESET="linux-profile-clang"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compiler)
      MATRIX_COMPILER="$2"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --gcc-profile-preset)
      GCC_PROFILE_PRESET="$2"
      shift 2
      ;;
    --clang-profile-preset)
      CLANG_PROFILE_PRESET="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

rm -rf "${BUILD_DIR}"
if [ "${MATRIX_COMPILER}" = "gcc" ]; then
  PRESET="${GCC_PROFILE_PRESET}"
else
  PRESET="${CLANG_PROFILE_PRESET}"
fi
echo "Using preset: ${PRESET}"

cmake -B "${BUILD_DIR}" --preset "${PRESET}"
cmake --build "${BUILD_DIR}" --preset "${PRESET}"

if [ "${MATRIX_COMPILER}" = "clang" ]; then
  (
    cd "${BUILD_DIR}"
    LLVM_PROFILE_FILE="/workspace/${BUILD_DIR}/dummy.profraw" ./KataglyphisCppProject
    llvm-profdata merge -sparse "/workspace/${BUILD_DIR}/dummy.profraw" -o "/workspace/${BUILD_DIR}/dummy.profdata"
    llvm-cov show ./KataglyphisCppProject -instr-profile="/workspace/${BUILD_DIR}/dummy.profdata" -format=text
  )
fi

( cd "${BUILD_DIR}" && perf record -F 99 --call-graph dwarf -- ./KataglyphisCppProject ) || true
( cd "${BUILD_DIR}" && ./perfTestSuite --benchmark_out=results.json --benchmark_out_format=json )

(
  cd "${BUILD_DIR}"
  ./KataglyphisCppProject
  if [[ -f gmon.out ]]; then
    gprof KataglyphisCppProject gmon.out > profile.txt || true
  else
    echo "gmon.out not found, skipping gprof."
  fi
)
