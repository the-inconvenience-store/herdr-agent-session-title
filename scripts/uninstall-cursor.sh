#!/bin/sh
# herdr plugin action: removes the Cursor Agent session-title hooks
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
cursor_dir="${HOME:?HOME is not set}/.cursor"
callback="$cursor_dir/herdr-agent-session-title-cursor.py"
hooks="$cursor_dir/hooks.json"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

python3 "$plugin_root/scripts/cursor-hooks-config.py" uninstall "$hooks" "$callback"

rm -f "$callback"
echo "uninstalled"
