#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if command -v node >/dev/null 2>&1; then
  node tests/test-opencode-extension.mjs
elif command -v bun >/dev/null 2>&1; then
  bun tests/test-opencode-extension.mjs
else
  echo "test-opencode-extension: SKIP (node or bun is required)"
fi
