#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SELF_DIR}/lib/common.sh"
init_repo_context

MATRIX_COMPILER="clang"
BUILD_DIR="build"
GCC_DEBUG_PRESET="linux-debug-GNU"
CLANG_DEBUG_PRESET="linux-debug-clang"
COVERAGE_JSON="coverage.json"

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
    --gcc-debug-preset)
      GCC_DEBUG_PRESET="$2"
      shift 2
      ;;
    --clang-debug-preset)
      CLANG_DEBUG_PRESET="$2"
      shift 2
      ;;
    --coverage-json)
      COVERAGE_JSON="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

mkdir -p "${WORKSPACE_ROOT}/docs/coverage"
mkdir -p "${WORKSPACE_ROOT}/docs/test-results"

if [ "${MATRIX_COMPILER}" = "gcc" ]; then
  PRESET="${GCC_DEBUG_PRESET}"
else
  PRESET="${CLANG_DEBUG_PRESET}"
fi
echo "Using preset: ${PRESET}"

CMAKE_EXTRA_ARGS=()
append_clang_gcc_toolchain_args "${MATRIX_COMPILER}" CMAKE_EXTRA_ARGS

cmake -B "${BUILD_DIR}" --preset "${PRESET}" "${CMAKE_EXTRA_ARGS[@]}"
cmake --build "${BUILD_DIR}" --preset "${PRESET}"

(
  cd "${BUILD_DIR}"
  ctest -C Debug --verbose --extra-verbose --debug -T test --output-on-failure --output-junit "${WORKSPACE_ROOT}/docs/test_results.xml"
)

if [ "${MATRIX_COMPILER}" = "clang" ]; then
  ./${BUILD_DIR}/first_fuzz_test
else
  echo "Compiled with GCC so no fuzz testing!"
fi

if [ "${MATRIX_COMPILER}" = "gcc" ]; then
  (
    cd "${BUILD_DIR}"
    gcovr --html-details "${WORKSPACE_ROOT}/docs/coverage/index.html" -r .
  )
else
  (
    cd "${BUILD_DIR}"
    llvm-profdata merge -sparse Test/compile/default.profraw -o compileTestSuite.profdata
    llvm-cov report ./compileTestSuite -instr-profile=compileTestSuite.profdata
    llvm-cov export ./compileTestSuite -format=text -instr-profile=compileTestSuite.profdata > "${WORKSPACE_ROOT}/${COVERAGE_JSON}"
    llvm-cov show ./compileTestSuite -instr-profile=compileTestSuite.profdata -format=html -output-dir "${WORKSPACE_ROOT}/docs/coverage"
  )
fi

clang-tidy -p=./${BUILD_DIR}/compile_commands.json $(find Src -name "*.cpp" -o -name "*.cc")

if [ "${MATRIX_COMPILER}" = "clang" ]; then
  clang++ --analyze -DUSE_RUST=1 -Xanalyzer -analyzer-output=html $(find Src -name "*.cpp" -o -name "*.cc") || true

  mkdir -p scan-build-reports
  scan-build -o scan-build-reports cmake --build "${WORKSPACE_ROOT}/${BUILD_DIR}" --preset "${CLANG_DEBUG_PRESET}" || true
fi
