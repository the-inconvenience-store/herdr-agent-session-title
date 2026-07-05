#!/bin/sh
# runs every test script; each one exits nonzero on failure
set -eu
cd "$(dirname "$0")/.."
found=0
for test_script in tests/test-*.sh; do
  [ -e "$test_script" ] || continue
  found=1
  echo "== $test_script"
  sh "$test_script"
done
[ "$found" = "1" ] || echo "no tests yet"
echo "all tests: OK"
