#!/usr/bin/env bash
#
# Negative compile tests for PurSocket type engine.
#
# Each .purs file in this directory (and subdirectories) MUST FAIL to compile.
# This script compiles each one individually and verifies that
# the compiler rejects it.
#
# Structure:
#   test-negative/*.purs           - compiled against src/**/*.purs only
#   test-negative/<subdir>/config  - extra source globs (one per line, # comments)
#   test-negative/<subdir>/*.purs  - compiled against src/**/*.purs + config globs
#
# Adding a new category is a file-drop operation:
#   1. Create a subdirectory under test-negative/
#   2. Add a `config` file with extra source globs (one per line)
#   3. Add .purs files that should fail to compile
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

# Run a single negative test.  Arguments:
#   $1 - path to the .purs file
#   $2 - display name
#   $@ (3+) - extra source globs (optional)
run_negative_test() {
  local test_file="$1"
  local test_name="$2"
  shift 2
  local extra_srcs=("$@")

  total=$((total + 1))

  # Attempt to compile the negative test file along with the src modules
  # and all dependencies.  We use purs compile directly (not spago) to
  # avoid including the main test suite.
  if purs compile \
    "$test_file" \
    "$PROJECT_ROOT/src/**/*.purs" \
    "$PROJECT_ROOT/.spago/p/*/src/**/*.purs" \
    "${extra_srcs[@]}" \
    2>/dev/null; then
    echo "FAIL: $test_name compiled successfully (should have failed)"
    failed=$((failed + 1))
  else
    echo "PASS: $test_name correctly failed to compile"
    passed=$((passed + 1))
  fi
}

# --- Core negative tests (top-level .purs files, no config needed) ---
for test_file in "$SCRIPT_DIR"/*.purs; do
  [ -f "$test_file" ] || continue
  test_name="$(basename "$test_file" .purs)"
  run_negative_test "$test_file" "$test_name"
done

# --- Subdirectory negative tests (discovered via config files) ---
for config_file in "$SCRIPT_DIR"/*/config; do
  [ -f "$config_file" ] || continue

  subdir="$(dirname "$config_file")"
  subdir_name="$(basename "$subdir")"

  # Read extra source globs from config, skipping comments and blank lines.
  extra_srcs=()
  while IFS= read -r line; do
    # Strip leading/trailing whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    extra_srcs+=("$PROJECT_ROOT/$line")
  done < "$config_file"

  for test_file in "$subdir"/*.purs; do
    [ -f "$test_file" ] || continue
    test_name="$subdir_name/$(basename "$test_file" .purs)"
    run_negative_test "$test_file" "$test_name" "${extra_srcs[@]}"
  done
done

echo ""
echo "Negative compile tests: $passed/$total passed, $failed/$total unexpected successes"

if [ "$failed" -gt 0 ]; then
  echo "ERROR: Some negative tests compiled when they should not have."
  exit 1
fi

echo "All negative compile tests passed."
exit 0
