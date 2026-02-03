#!/usr/bin/env bash
#
# Negative compile tests for PurSocket type engine.
#
# Each .purs file in this directory MUST FAIL to compile.
# This script compiles each one individually and verifies that
# the compiler rejects it.
#
# Usage:  bash test-negative/run-negative-tests.sh
# Exit:   0 if all negative tests fail to compile (expected)
#         1 if any negative test compiles (unexpected -- bug in type engine)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

passed=0
failed=0
total=0

for test_file in "$SCRIPT_DIR"/*.purs; do
  test_name="$(basename "$test_file" .purs)"
  total=$((total + 1))

  # Attempt to compile the negative test file along with the src modules
  # and all dependencies.  We use purs compile directly (not spago) to
  # avoid including the main test suite.
  if purs compile \
    "$test_file" \
    "$PROJECT_ROOT/src/**/*.purs" \
    "$PROJECT_ROOT/.spago/p/*/src/**/*.purs" \
    2>/dev/null; then
    echo "FAIL: $test_name compiled successfully (should have failed)"
    failed=$((failed + 1))
  else
    echo "PASS: $test_name correctly failed to compile"
    passed=$((passed + 1))
  fi
done

echo ""
echo "Negative compile tests: $passed/$total passed, $failed/$total unexpected successes"

if [ "$failed" -gt 0 ]; then
  echo "ERROR: Some negative tests compiled when they should not have."
  exit 1
fi

echo "All negative compile tests passed."
exit 0
