#!/bin/sh
# herdr plugin action: prints Codex notification integration status
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
codex_dir="${CODEX_HOME:-$HOME/.codex}"
callback="$codex_dir/herdr-agent-session-title-codex.py"
state="$codex_dir/herdr-session-title-notify-state.json"
config="$codex_dir/config.toml"

python3 "$plugin_root/scripts/codex-notify-config.py" \
  status "$config" "$state" "$callback"
