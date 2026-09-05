#!/bin/sh
# herdr plugin action: disables and removes the Hermes session-title plugin link
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
plugin_root=$(cd "$plugin_root" && pwd -P)
source_dir="$plugin_root/hermes-plugin"
hermes_home="${HERMES_HOME:-${HOME:?HOME is not set}/.hermes}"
destination="$hermes_home/plugins/herdr-agent-session-title"

if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
  echo "uninstalled Hermes integration"
  exit 0
fi
if [ ! -L "$destination" ] || [ "$(readlink "$destination")" != "$source_dir" ]; then
  echo "refusing to remove unrelated Hermes plugin path: $destination" >&2
  exit 1
fi

command -v hermes >/dev/null 2>&1 || { echo "hermes is required" >&2; exit 1; }
hermes plugins disable herdr-agent-session-title >/dev/null
rm "$destination"

echo "uninstalled Hermes integration"
echo "note: already-running Hermes processes unload the plugin on restart"
