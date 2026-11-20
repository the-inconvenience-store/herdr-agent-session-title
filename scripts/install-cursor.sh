#!/bin/sh
# herdr plugin action: registers the Cursor Agent session-title hooks
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
cursor_dir="${HOME:?HOME is not set}/.cursor"
callback="$cursor_dir/herdr-agent-session-title-cursor.py"
hooks="$cursor_dir/hooks.json"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

mkdir -p "$cursor_dir"
cp "$plugin_root/scripts/herdr-agent-session-title-cursor.py" "$callback"
chmod +x "$callback"

python3 "$plugin_root/scripts/cursor-hooks-config.py" install "$hooks" "$callback"

echo "installed: $callback"
echo "note: already-running Cursor Agent sessions pick up hook changes on restart"
