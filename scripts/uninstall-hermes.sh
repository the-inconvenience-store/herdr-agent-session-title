#!/bin/sh
# herdr plugin action: disables and removes the Hermes session-title plugin
set -eu

hermes_home="${HERMES_HOME:-${HOME:?HOME is not set}/.hermes}"
destination="$hermes_home/plugins/herdr-agent-session-title"

if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
  echo "uninstalled Hermes integration"
  exit 0
fi
if [ ! -f "$destination/.herdr-integration" ]; then
  echo "refusing to remove unrelated Hermes plugin path: $destination" >&2
  exit 1
fi

command -v hermes >/dev/null 2>&1 || { echo "hermes is required" >&2; exit 1; }
hermes plugins disable herdr-agent-session-title >/dev/null
rm -rf "$destination"

echo "uninstalled Hermes integration"
echo "note: already-running Hermes processes unload the plugin on restart"
