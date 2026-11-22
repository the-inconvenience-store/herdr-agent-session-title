#!/bin/sh
# herdr plugin action: unregisters and removes the opencode TUI plugin
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
config_home="${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}"
config_dir="$config_home/opencode"
install_dir="$config_dir/herdr-agent-session-title"
entry="./herdr-agent-session-title"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

if [ -e "$install_dir" ] && [ ! -f "$install_dir/.herdr-integration" ]; then
  echo "refusing to remove unrecognized opencode plugin: $install_dir" >&2
  exit 1
fi

python3 "$plugin_root/scripts/opencode-cli-config.py" \
  uninstall "$config_dir/cli.json" "$entry"
rm -rf "$install_dir"

echo "uninstalled opencode integration"
