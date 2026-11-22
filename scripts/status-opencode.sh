#!/bin/sh
# herdr plugin action: prints opencode TUI plugin integration status
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
config_home="${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}"
config_dir="$config_home/opencode"
install_dir="$config_dir/herdr-agent-session-title"
entry="./herdr-agent-session-title"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

result=0
if [ -f "$install_dir/.herdr-integration" ] && [ -f "$install_dir/tui.js" ]; then
  echo "plugin files: installed"
else
  echo "plugin files: NOT installed"
  result=1
fi
python3 "$plugin_root/scripts/opencode-cli-config.py" \
  status "$config_dir/cli.json" "$entry" || result=1
exit "$result"
