#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
export HERDR_PLUGIN_ROOT="$PWD"
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$HOME/.cursor"
cat > "$HOME/.cursor/hooks.json" <<'JSON'
{
  "version": 1,
  "totallyUnrelated": true,
  "hooks": {
    "sessionStart": [
      {"command": "bash '/Users/someone/.cursor/herdr-agent-state.sh' session"}
    ],
    "stop": [
      {"command": "other-tool stop", "loop_limit": 10}
    ],
    "beforeSubmitPrompt": [
      {"command": "other-tool prompt"}
    ]
  }
}
JSON

sh scripts/install-cursor.sh >/dev/null
sh scripts/install-cursor.sh >/dev/null

python3 - "$HOME/.cursor/hooks.json" <<'PY'
import json
import sys

config = json.load(open(sys.argv[1]))
hooks = config["hooks"]
assert config["version"] == 1, config
assert config["totallyUnrelated"] is True, config

session_start = [e["command"] for e in hooks["sessionStart"]]
assert len(session_start) == 2, session_start
assert session_start[0].startswith("bash "), session_start
ours = [c for c in session_start if "herdr-agent-session-title-cursor.py" in c]
assert len(ours) == 1, session_start

stop = [e["command"] for e in hooks["stop"]]
assert stop[0] == "other-tool stop", stop
assert hooks["stop"][0]["loop_limit"] == 10, hooks["stop"]
assert len([c for c in stop if "herdr-agent-session-title-cursor.py" in c]) == 1, stop
assert hooks["beforeSubmitPrompt"] == [{"command": "other-tool prompt"}], hooks
print("cursor hooks install, merge, and idempotency: OK")
PY

[ -x "$HOME/.cursor/herdr-agent-session-title-cursor.py" ] ||
  fail "cursor callback copy missing"
[ -f "$HOME/.cursor/hooks.json.bak-herdr-agent-session-title" ] ||
  fail "backup missing"

out=$(sh scripts/status-cursor.sh)
echo "$out" | grep -q "callback script: installed" || fail "expected installed, got: $out"
echo "$out" | grep -q "Cursor hooks: registered" || fail "expected registered, got: $out"

sh scripts/uninstall-cursor.sh >/dev/null

python3 - "$HOME/.cursor/hooks.json" <<'PY'
import json
import sys

config = json.load(open(sys.argv[1]))
hooks = config["hooks"]
assert [e["command"] for e in hooks["sessionStart"]] == [
    "bash '/Users/someone/.cursor/herdr-agent-state.sh' session"
], hooks
assert hooks["stop"] == [{"command": "other-tool stop", "loop_limit": 10}], hooks
assert hooks["beforeSubmitPrompt"] == [{"command": "other-tool prompt"}], hooks
assert "herdr-agent-session-title-cursor.py" not in json.dumps(config), config
print("cursor hooks uninstall restoration: OK")
PY

[ ! -e "$HOME/.cursor/herdr-agent-session-title-cursor.py" ] ||
  fail "cursor callback not removed"

out=$(sh scripts/status-cursor.sh)
echo "$out" | grep -q "callback script: NOT installed" || fail "expected NOT installed, got: $out"

# Malformed hooks.json must fail loudly without modifying the file.
malformed_dir=$(mktemp -d)
export HOME="$malformed_dir"
mkdir -p "$HOME/.cursor"
printf 'not json {{{' > "$HOME/.cursor/hooks.json"
cp "$HOME/.cursor/hooks.json" "$HOME/.cursor/hooks.json.orig"
if sh scripts/install-cursor.sh >/dev/null 2>&1; then
  fail "install must fail on malformed hooks.json"
fi
cmp "$HOME/.cursor/hooks.json" "$HOME/.cursor/hooks.json.orig" ||
  fail "malformed hooks.json was modified"
rm -rf "$malformed_dir"

echo "test-cursor-install: OK"
