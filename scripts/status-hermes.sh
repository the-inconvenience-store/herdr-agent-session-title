#!/bin/sh
# herdr plugin action: prints Hermes session-title integration status
set -eu

hermes_home="${HERMES_HOME:-${HOME:?HOME is not set}/.hermes}"
destination="$hermes_home/plugins/herdr-agent-session-title"

command -v hermes >/dev/null 2>&1 || { echo "hermes is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

if [ ! -f "$destination/.herdr-integration" ]; then
  echo "not installed"
  exit 1
fi

hermes plugins list --user --json | python3 -c '
import json
import sys

plugins = json.load(sys.stdin)
plugin = next((item for item in plugins if item.get("name") == "herdr-agent-session-title"), None)
if plugin is None:
    print("installed but not discovered: herdr-agent-session-title")
    raise SystemExit(1)
if plugin.get("status") != "enabled":
    print("installed but disabled: herdr-agent-session-title")
    raise SystemExit(1)
print("installed and enabled: herdr-agent-session-title")
'
