#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
unset HERDR_SOCKET_PATH 2>/dev/null || true
export HERDR_PLUGIN_ROOT="$PWD"
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$HOME/.claude"

out=$(sh scripts/status.sh)
echo "$out" | grep -q "hook script: NOT installed" || fail "expected NOT installed, got: $out"

sh scripts/install.sh >/dev/null
out=$(sh scripts/status.sh)
echo "$out" | grep -q "hook script: installed" || fail "expected installed, got: $out"
echo "$out" | grep -q "SessionStart: registered" || fail "expected SessionStart registered, got: $out"
echo "$out" | grep -q "UserPromptSubmit: registered" || fail "expected UserPromptSubmit registered, got: $out"
echo "$out" | grep -q "Stop: registered" || fail "expected Stop registered, got: $out"

# malformed settings.json must not break the exit-0 contract
printf 'not json {{{' > "$HOME/.claude/settings.json"
out=$(sh scripts/status.sh) || fail "status.sh must exit 0 on malformed settings.json"
echo "$out" | grep -q "settings.json: unreadable or malformed" || fail "expected malformed diagnostic, got: $out"

echo "test-status: OK"
