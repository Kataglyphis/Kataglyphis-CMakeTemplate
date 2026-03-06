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

# Keep project coverage focused on first-party code by excluding tests and vendored deps.
COVERAGE_IGNORE_REGEX='(^|[\\/])(ExternalLib|_deps|Test)([\\/]|$)'

if [ "${MATRIX_COMPILER}" = "gcc" ]; then
  PRESET="${GCC_DEBUG_PRESET}"
else
  PRESET="${CLANG_DEBUG_PRESET}"
fi
echo "Using preset: ${PRESET}"

CMAKE_EXTRA_ARGS=("-DCOMPILER_CACHE:STRING=ccache")
append_clang_gcc_toolchain_args "${MATRIX_COMPILER}" CMAKE_EXTRA_ARGS

cmake_configure_build "${BUILD_DIR}" "${PRESET}" "${CMAKE_EXTRA_ARGS[@]}"

(
  cd "${BUILD_DIR}"
  ctest -C Debug --verbose --extra-verbose --debug -T test --output-on-failure --output-junit "${WORKSPACE_ROOT}/docs/test_results.xml"
)

if [ "${MATRIX_COMPILER}" = "clang" ]; then
  ./${BUILD_DIR}/first_fuzz_test
else
  echo "Compiled with GCC so no fuzz testing!"
fi

echo "=========================================="
echo "Starting ThreadSanitizer (TSan) build..."
echo "=========================================="
TSAN_BUILD_DIR="${BUILD_DIR}-tsan"
if [ "${MATRIX_COMPILER}" = "gcc" ]; then
  TSAN_PRESET="linux-debug-tsan-GNU"
else
  TSAN_PRESET="linux-debug-tsan-clang"
fi

cmake_configure_build "${TSAN_BUILD_DIR}" "${TSAN_PRESET}" "${CMAKE_EXTRA_ARGS[@]}"

echo "Running tests for TSan build..."
(
  cd "${TSAN_BUILD_DIR}"
  ctest -C Debug --output-on-failure
)
echo "TSan build and tests completed successfully."

if [ "${MATRIX_COMPILER}" = "gcc" ]; then
  (
    cd "${BUILD_DIR}"
    gcovr --html-details "${WORKSPACE_ROOT}/docs/coverage/index.html" -r .
  )
else
  (
    cd "${BUILD_DIR}"
    llvm-profdata merge -sparse Test/compile/default.profraw -o compileTestSuite.profdata
    llvm-cov report ./compileTestSuite -instr-profile=compileTestSuite.profdata \
      -ignore-filename-regex="${COVERAGE_IGNORE_REGEX}"
    llvm-cov export ./compileTestSuite -format=text -instr-profile=compileTestSuite.profdata \
      -ignore-filename-regex="${COVERAGE_IGNORE_REGEX}" > "${WORKSPACE_ROOT}/${COVERAGE_JSON}"
    llvm-cov show ./compileTestSuite -instr-profile=compileTestSuite.profdata -format=html \
      -ignore-filename-regex="${COVERAGE_IGNORE_REGEX}" -output-dir "${WORKSPACE_ROOT}/docs/coverage"
  )
fi

mapfile -t CLANG_ANALYZER_CANDIDATES < <(find Src -type f \( -name "*.cpp" -o -name "*.cc" \) | sort)
if [ "${#CLANG_ANALYZER_CANDIDATES[@]}" -eq 0 ]; then
  echo "No C++ sources found for clang-tidy analysis in Src/"
  exit 1
fi

if [ "${MATRIX_COMPILER}" = "clang" ]; then
  "${SELF_DIR}/run_static_analysis_format.sh" \
    --tidy-only \
    --allow-tidy-failure \
    --compile-db "${WORKSPACE_ROOT}/${BUILD_DIR}" \
    --run-clang-analyzer \
    --run-scan-build \
    --scan-build-preset "${CLANG_DEBUG_PRESET}"
else
  "${SELF_DIR}/run_static_analysis_format.sh" \
    --tidy-only \
    --allow-tidy-failure \
    --compile-db "${WORKSPACE_ROOT}/${BUILD_DIR}"
fi

if [ "${MATRIX_COMPILER}" = "clang" ]; then
  ./${BUILD_DIR}/first_fuzz_test --fuzz=MyTestSuite.IntegerAdditionCommutes --fuzz_for=30s
fi
