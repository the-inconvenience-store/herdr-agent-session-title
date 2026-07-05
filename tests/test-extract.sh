#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
py="scripts/herdr-claude-session-title.py"
fx="tests/fixtures"
fail() { echo "FAIL: $1" >&2; exit 1; }

title=$(python3 "$py" extract "$fx/transcript-custom-title.jsonl" "sid-1")
[ "$title" = "second-name" ] || fail "expected last rename to win, got: $title"

title=$(python3 "$py" extract "$fx/transcript-no-title.jsonl" "sid-2")
[ "$title" = "Automatic summary title" ] || fail "expected summary fallback, got: $title"

title=$(python3 "$py" extract "$fx/transcript-garbage.jsonl" "sid-3")
[ "$title" = "valid-after-garbage" ] || fail "expected title despite garbage lines, got: $title"

title=$(python3 "$py" extract "$fx/transcript-long-title.jsonl" "sid-5")
[ "${#title}" -eq 120 ] || fail "expected 120-char truncation, got length: ${#title}"

if python3 "$py" extract "$fx/missing.jsonl" "sid-4" >/dev/null 2>&1; then
  fail "expected nonzero exit when transcript missing and session not in index"
fi

title=$(python3 "$py" extract "$fx/transcript-control-chars.jsonl" "sid-6")
[ "$title" = "bad title here" ] || fail "expected control chars collapsed to spaces, got: $title"

title=$(python3 "$py" extract "$fx/transcript-ai-title.jsonl" "sid-7")
[ "$title" = "auto generated name v2" ] || fail "expected last ai-title as fallback, got: $title"

title=$(python3 "$py" extract "$fx/transcript-ai-and-custom.jsonl" "sid-8")
[ "$title" = "user-chosen-name" ] || fail "expected custom-title to beat later ai-title, got: $title"

echo "test-extract: OK"
