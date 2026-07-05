#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
export HERDR_PLUGIN_ROOT="$PWD"
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "other-tool hook"}]}
    ]
  },
  "model": "opus"
}
JSON

sh scripts/install.sh >/dev/null
sh scripts/install.sh >/dev/null

python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
hooks = settings["hooks"]
marker = "herdr-claude-session-title.sh"
for event in ["SessionStart", "UserPromptSubmit", "Stop"]:
    ours = [h for e in hooks.get(event, []) for h in e.get("hooks", [])
            if marker in str(h.get("command", ""))]
    assert len(ours) == 1, ("duplicate or missing registration", event, ours)
    assert ours[0].get("timeout") == 10, ours
foreign = [h for e in hooks["Stop"] for h in e.get("hooks", [])
           if h.get("command") == "other-tool hook"]
assert len(foreign) == 1, ("foreign hook lost", foreign)
assert settings["model"] == "opus", "unrelated settings must survive"
session_start = hooks["SessionStart"]
ours_entry = [e for e in session_start
              if any(marker in str(h.get("command", "")) for h in e.get("hooks", []))]
assert ours_entry[0].get("matcher") == "*", ours_entry
print("install idempotency: OK")
PY

[ -x "$HOME/.claude/hooks/herdr-claude-session-title.sh" ] || fail "hook sh copy missing"
[ -f "$HOME/.claude/hooks/herdr-claude-session-title.py" ] || fail "hook py copy missing"
[ -f "$HOME/.claude/settings.json.bak-claude-session-title" ] || fail "backup missing"

sh scripts/uninstall.sh >/dev/null

python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
raw = json.dumps(settings)
assert "herdr-claude-session-title" not in raw, raw
foreign = [h for e in settings["hooks"]["Stop"] for h in e.get("hooks", [])
           if h.get("command") == "other-tool hook"]
assert len(foreign) == 1, ("foreign hook lost on uninstall", foreign)
print("uninstall cleanup: OK")
PY

[ ! -e "$HOME/.claude/hooks/herdr-claude-session-title.sh" ] || fail "hook sh copy not removed"
[ ! -e "$HOME/.claude/hooks/herdr-claude-session-title.py" ] || fail "hook py copy not removed"

[ -f "$HOME/.claude/settings.json.bak-claude-session-title" ] || fail "backup missing after uninstall"

# malformed settings.json: install must fail loud and leave the file untouched
malformed_dir=$(mktemp -d)
cat > "$malformed_dir/settings.json" <<'JSON'
{
  "hooks": {
    "Stop": "not-a-list"
  }
}
JSON
cp "$malformed_dir/settings.json" "$malformed_dir/settings.json.orig"
export HOME="$malformed_dir"
mkdir -p "$HOME/.claude"
mv "$malformed_dir/settings.json" "$HOME/.claude/settings.json"
if sh scripts/install.sh >/dev/null 2>&1; then
  fail "install must fail on malformed settings"
fi
cmp "$HOME/.claude/settings.json" "$malformed_dir/settings.json.orig" || fail "malformed settings.json was modified"
rm -rf "$malformed_dir"
export HOME="$tmp"

echo "test-install: OK"
