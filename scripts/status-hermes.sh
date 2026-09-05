#!/bin/sh
# herdr plugin action: prints Hermes session-title integration status
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
plugin_root=$(cd "$plugin_root" && pwd -P)
source_dir="$plugin_root/hermes-plugin"
hermes_home="${HERMES_HOME:-${HOME:?HOME is not set}/.hermes}"
destination="$hermes_home/plugins/herdr-agent-session-title"

command -v hermes >/dev/null 2>&1 || { echo "hermes is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

if [ ! -L "$destination" ]; then
  echo "not installed"
  exit 1
fi
if [ "$(readlink "$destination")" != "$source_dir" ]; then
  echo "installed path is not owned by this Herdr plugin: $destination"
  exit 1
fi

hermes plugins list --user --json | python3 -c '
import json
import sys

plugins = json.load(sys.stdin)
plugin = next((item for item in plugins if item.get("name") == "herdr-agent-session-title"), None)
if plugin is None:
    print("linked but not discovered: herdr-agent-session-title")
    raise SystemExit(1)
if plugin.get("status") != "enabled":
    print("installed but disabled: herdr-agent-session-title")
    raise SystemExit(1)
print("installed and enabled: herdr-agent-session-title")
'
