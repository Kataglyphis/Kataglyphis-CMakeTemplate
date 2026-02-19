#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

git config --global --add safe.directory /workspace || true

DOCS_OUT="build/build/html"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-out)
      DOCS_OUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

uv venv
. ".venv/bin/activate"
uv pip install -r requirements.txt

cp ${DOCS_OUT}/*.svg ./docs/source/_static || true
cd docs/source
uv run python graphviz_generator.py
cd ..
uv run make html

shopt -s globstar nullglob
mkdir -p docs/test-results
for f in /workspace/**/*.xml; do
  [ -s "$f" ] || { echo "Skipping empty file: $f"; continue; }
  if grep -qE "<testsuites|<testsuite" "$f"; then
    if junit2html "$f" "/workspace/docs/test-results/$(basename "$f" .xml).html"; then
      echo "Converted: $(basename "$f")"
    else
      echo "junit2html failed for: $f — skipping"
    fi
  else
    echo "Not JUnit XML, skipping: $f"
  fi
done

if ! command -v pandoc >/dev/null 2>&1; then
  apt-get update
  apt-get install -y pandoc
fi

mkdir -p "/workspace/docs/test-results-md"
html_files=("/workspace"/docs/test-results/*.html)
if [ ${#html_files[@]} -eq 0 ]; then
  echo "No HTML files found in docs/test-results. Skipping pandoc conversion."
  exit 0
fi
for f in "${html_files[@]}"; do
  pandoc "$f" --verbose -f html -t gfm -o "/workspace/docs/test-results-md/$(basename "$f" .html).md"
done

mkdir -p docs/source/test-results
if [ -d "docs/test-results-md" ] && [ "$(ls -A docs/test-results-md || true)" ]; then
  cp -r docs/test-results-md/* docs/source/test-results/
  echo "Copied markdown test results to Sphinx source"
else
  echo "No markdown test results to copy (docs/test-results-md is empty or missing)"
fi

SITE_DIR="/workspace/docs/build/html"
mkdir -p "$SITE_DIR"
if [[ -d "/workspace/docs/coverage" ]]; then
  mkdir -p "$SITE_DIR/coverage"
  cp -r "/workspace/docs/coverage/." "$SITE_DIR/coverage/"
fi
if [[ -d "/workspace/docs/test-results" ]]; then
  mkdir -p "$SITE_DIR/test-results"
  cp -r "/workspace/docs/test-results/." "$SITE_DIR/test-results/"
fi

OWNER_UID=$(stat -c "%u" /workspace)
OWNER_GID=$(stat -c "%g" /workspace)
echo "Fixing ownership of docs/ to ${OWNER_UID}:${OWNER_GID}"
chown -R ${OWNER_UID}:${OWNER_GID} /workspace/docs || true
