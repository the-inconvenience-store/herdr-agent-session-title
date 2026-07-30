#!/bin/sh
# herdr plugin action: removes the Claude Code status-line integration
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
callback="$claude_dir/herdr-claude-session-title.py"
state="$claude_dir/herdr-session-title-statusline-state.json"
settings="$claude_dir/settings.json"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

python3 "$plugin_root/scripts/claude-statusline-config.py" \
  uninstall "$settings" "$state" "$callback"

rm -f \
  "$callback" \
  "$claude_dir/hooks/herdr-claude-session-title.sh" \
  "$claude_dir/hooks/herdr-claude-session-title.py"
echo "uninstalled"
