#!/bin/sh
# herdr plugin action: removes the Codex notification callback
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
codex_dir="${CODEX_HOME:-$HOME/.codex}"
callback="$codex_dir/herdr-agent-session-title-codex.py"
state="$codex_dir/herdr-session-title-notify-state.json"
config="$codex_dir/config.toml"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
python3 "$plugin_root/scripts/codex-notify-config.py" \
  uninstall "$config" "$state" "$callback"
rm -f "$callback" "$codex_dir/herdr-codex-session-title.py"
echo "uninstalled Codex integration"
