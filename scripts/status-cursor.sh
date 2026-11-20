#!/bin/sh
# herdr plugin action: prints Cursor Agent session-title integration status
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
cursor_dir="${HOME:?HOME is not set}/.cursor"
callback="$cursor_dir/herdr-agent-session-title-cursor.py"
hooks="$cursor_dir/hooks.json"

python3 "$plugin_root/scripts/cursor-hooks-config.py" \
  status "$hooks" "$callback" || true

if [ -n "${HERDR_SOCKET_PATH:-}" ] && [ -S "$HERDR_SOCKET_PATH" ]; then
  echo "herdr socket: reachable ($HERDR_SOCKET_PATH)"
else
  echo "herdr socket: not available in this environment"
fi
