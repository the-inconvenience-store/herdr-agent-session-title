#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
export HERDR_PLUGIN_ROOT="$PWD"
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$HOME/.claude/hooks"
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "other-tool hook"}]},
      {"hooks": [{"type": "command", "command": "sh '/old/herdr-claude-session-title.sh'"}]}
    ],
    "SessionStart": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "sh '/old/herdr-claude-session-title.sh'"}]}
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "sh /existing/statusline.sh",
    "padding": 2,
    "refreshInterval": 5
  },
  "model": "opus"
}
JSON
touch "$HOME/.claude/hooks/herdr-claude-session-title.sh"
touch "$HOME/.claude/hooks/herdr-claude-session-title.py"

sh scripts/install.sh >/dev/null
sh scripts/install.sh >/dev/null

python3 - \
  "$HOME/.claude/settings.json" \
  "$HOME/.claude/herdr-session-title-statusline-state.json" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1]))
status_line = settings["statusLine"]
assert status_line["type"] == "command", status_line
assert status_line["command"].endswith("herdr-claude-session-title.py"), status_line
assert status_line["padding"] == 2, status_line
assert status_line["refreshInterval"] == 5, status_line
assert settings["model"] == "opus", settings

raw = json.dumps(settings)
assert "herdr-claude-session-title.sh" not in raw, raw
foreign = [
    hook
    for entry in settings["hooks"]["Stop"]
    for hook in entry.get("hooks", [])
    if hook.get("command") == "other-tool hook"
]
assert len(foreign) == 1, ("foreign hook lost", foreign)

state = json.load(open(sys.argv[2]))
assert state["previous_status_line"] == {
    "type": "command",
    "command": "sh /existing/statusline.sh",
    "padding": 2,
    "refreshInterval": 5,
}, state
print("status-line install, migration, and idempotency: OK")
PY

[ -x "$HOME/.claude/herdr-claude-session-title.py" ] ||
  fail "status-line callback copy missing"
[ ! -e "$HOME/.claude/hooks/herdr-claude-session-title.sh" ] ||
  fail "legacy hook shell copy not removed"
[ ! -e "$HOME/.claude/hooks/herdr-claude-session-title.py" ] ||
  fail "legacy hook Python copy not removed"
[ -f "$HOME/.claude/settings.json.bak-claude-session-title" ] ||
  fail "backup missing"

sh scripts/uninstall.sh >/dev/null

python3 - "$HOME/.claude/settings.json" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1]))
assert settings["statusLine"] == {
    "type": "command",
    "command": "sh /existing/statusline.sh",
    "padding": 2,
    "refreshInterval": 5,
}, settings
foreign = [
    hook
    for entry in settings["hooks"]["Stop"]
    for hook in entry.get("hooks", [])
    if hook.get("command") == "other-tool hook"
]
assert len(foreign) == 1, ("foreign hook lost on uninstall", foreign)
assert "herdr-claude-session-title" not in json.dumps(settings), settings
print("status-line uninstall restoration: OK")
PY

[ ! -e "$HOME/.claude/herdr-claude-session-title.py" ] ||
  fail "status-line callback not removed"
[ ! -e "$HOME/.claude/herdr-session-title-statusline-state.json" ] ||
  fail "status-line integration state not removed"

# Malformed JSON must fail loudly without modifying the settings file.
malformed_dir=$(mktemp -d)
export HOME="$malformed_dir"
mkdir -p "$HOME/.claude"
printf 'not json {{{' > "$HOME/.claude/settings.json"
cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.orig"
if sh scripts/install.sh >/dev/null 2>&1; then
  fail "install must fail on malformed settings"
fi
cmp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.orig" ||
  fail "malformed settings.json was modified"
rm -rf "$malformed_dir"

echo "test-install: OK"
