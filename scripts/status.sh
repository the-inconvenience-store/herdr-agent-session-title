#!/bin/sh
# herdr plugin action: prints Claude status-line integration status
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
callback="$claude_dir/herdr-claude-session-title.py"
state="$claude_dir/herdr-session-title-statusline-state.json"
settings="$claude_dir/settings.json"

python3 "$plugin_root/scripts/claude-statusline-config.py" \
  status "$settings" "$state" "$callback" || true

if [ -n "${HERDR_SOCKET_PATH:-}" ] && [ -S "$HERDR_SOCKET_PATH" ]; then
  echo "herdr socket: reachable ($HERDR_SOCKET_PATH)"
else
  echo "herdr socket: not available in this environment"
fi
