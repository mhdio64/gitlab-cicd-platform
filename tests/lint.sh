#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Running YAML validation..."
if command -v yamllint >/dev/null 2>&1; then
    yamllint "${ROOT_DIR}"
else
    echo "yamllint not installed, skipping yaml linting."
fi

echo "==> Running ansible-lint..."
if command -v ansible-lint >/dev/null 2>&1; then
    cd "${ROOT_DIR}"
    ansible-lint
else
    echo "ansible-lint not found in PATH."
    exit 1
fi

echo "==> All lint checks passed successfully!"
