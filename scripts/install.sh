#!/bin/sh
# herdr plugin action: registers the Claude Code status-line integration
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
callback="$claude_dir/herdr-claude-session-title.py"
state="$claude_dir/herdr-session-title-statusline-state.json"
settings="$claude_dir/settings.json"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

mkdir -p "$claude_dir"
cp "$plugin_root/scripts/herdr-claude-session-title.py" "$callback"
chmod +x "$callback"

python3 "$plugin_root/scripts/claude-statusline-config.py" \
  install "$settings" "$state" "$callback"

# Clean up files left by releases that used Claude hooks.
rm -f \
  "$claude_dir/hooks/herdr-claude-session-title.sh" \
  "$claude_dir/hooks/herdr-claude-session-title.py"

echo "installed: $callback"
echo "note: already-running Claude Code sessions pick up status-line changes on restart"
