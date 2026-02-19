#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

git config --global --add safe.directory /workspace || true

BUILD_RELEASE_DIR="build-release"
CLANG_RELEASE_PRESET="linux-release-clang"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-release-dir)
      BUILD_RELEASE_DIR="$2"
      shift 2
      ;;
    --clang-release-preset)
      CLANG_RELEASE_PRESET="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

cmake -B "${BUILD_RELEASE_DIR}" --preset "${CLANG_RELEASE_PRESET}"
cmake --build "${BUILD_RELEASE_DIR}" --preset "${CLANG_RELEASE_PRESET}"
cmake --build "${BUILD_RELEASE_DIR}" --target package
(
  cd "${BUILD_RELEASE_DIR}"
  valgrind --tool=callgrind ./KataglyphisCppProject
)
