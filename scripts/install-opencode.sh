#!/bin/sh
# herdr plugin action: installs an opencode TUI plugin and registers it in cli.json
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
config_home="${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}"
config_dir="$config_home/opencode"
install_dir="$config_dir/herdr-agent-session-title"
entry="./herdr-agent-session-title"
staging="$install_dir.tmp.$$"

command -v opencode >/dev/null 2>&1 || { echo "opencode is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

# TUI plugins listed in cli.json are an opencode 2.x feature. Refuse a version
# that is known to be older instead of installing something that never loads.
major=$(opencode --version 2>/dev/null | sed -n 's/^[^0-9]*\([0-9][0-9]*\)\..*/\1/p' | head -n 1)
if [ -n "$major" ] && [ "$major" -lt 2 ]; then
  echo "opencode 2.x or newer is required (found major version $major)" >&2
  exit 1
fi

if [ -e "$install_dir" ] && [ ! -f "$install_dir/.herdr-integration" ]; then
  echo "refusing to replace unrecognized opencode plugin: $install_dir" >&2
  exit 1
fi

# Fail before changing anything if cli.json cannot be merged safely.
python3 "$plugin_root/scripts/opencode-cli-config.py" check "$config_dir/cli.json"

rm -rf "$staging"
trap 'rm -rf "$staging"' EXIT HUP INT TERM
mkdir -p "$staging"
cp "$plugin_root/scripts/herdr-agent-session-title-opencode.mjs" "$staging/tui.js"
printf '%s\n' 'HERDR_INTEGRATION_ID=opencode-session-title' > "$staging/.herdr-integration"
rm -rf "$install_dir"
mv "$staging" "$install_dir"
trap - EXIT HUP INT TERM

python3 "$plugin_root/scripts/opencode-cli-config.py" \
  install "$config_dir/cli.json" "$entry"

echo "installed: $install_dir"
echo "note: already-running opencode sessions load the plugin on restart"
