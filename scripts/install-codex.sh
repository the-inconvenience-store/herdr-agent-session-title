#!/bin/sh
# herdr plugin action: registers a Codex notification callback (not a hook)
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
codex_dir="${CODEX_HOME:-$HOME/.codex}"
callback="$codex_dir/herdr-codex-session-title.py"
state="$codex_dir/herdr-session-title-notify-state.json"
config="$codex_dir/config.toml"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
mkdir -p "$codex_dir"
cp "$plugin_root/scripts/herdr-codex-session-title.py" "$callback"
chmod +x "$callback"

python3 "$plugin_root/scripts/codex-notify-config.py" \
  install "$config" "$state" "$callback"

echo "installed: $callback"
echo "note: already-running Codex sessions pick up notify changes on restart"
