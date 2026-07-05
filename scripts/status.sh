#!/bin/sh
# herdr plugin action: prints hook installation status (read-only)
set -eu

claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
hook_sh="$claude_dir/hooks/herdr-claude-session-title.sh"
settings_path="$claude_dir/settings.json"

if [ -x "$hook_sh" ]; then
  echo "hook script: installed ($hook_sh)"
else
  echo "hook script: NOT installed"
fi

if [ -f "$settings_path" ] && command -v python3 >/dev/null 2>&1; then
  SETTINGS_PATH="$settings_path" python3 - <<'PY'
import json
import os

settings = json.load(open(os.environ["SETTINGS_PATH"], encoding="utf-8"))
marker = "herdr-claude-session-title.sh"
for event in ["SessionStart", "UserPromptSubmit", "Stop"]:
    count = sum(
        1
        for entry in settings.get("hooks", {}).get(event, [])
        if isinstance(entry, dict)
        for h in entry.get("hooks", [])
        if isinstance(h, dict) and marker in str(h.get("command", ""))
    )
    status = "registered" if count == 1 else "{} entries".format(count)
    print("{}: {}".format(event, status))
PY
else
  echo "settings.json: not found or python3 missing"
fi

if [ -n "${HERDR_SOCKET_PATH:-}" ] && [ -S "$HERDR_SOCKET_PATH" ]; then
  echo "herdr socket: reachable ($HERDR_SOCKET_PATH)"
else
  echo "herdr socket: not available in this environment"
fi
