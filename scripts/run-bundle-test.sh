#!/usr/bin/env bash
# Browser bundle smoke test.
# Requires spago build to have completed first.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Creating browser bundle..."
node scripts/bundle-browser.mjs

echo ""
echo "Verifying bundle..."
if [ -s dist/PurSocket.bundle.js ]; then
  SIZE=$(wc -c < dist/PurSocket.bundle.js)
  echo "Browser bundle is valid: dist/PurSocket.bundle.js ($SIZE bytes)"
  exit 0
else
  echo "ERROR: Bundle file missing or empty"
  exit 1
fi
