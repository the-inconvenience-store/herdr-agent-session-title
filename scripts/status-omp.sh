#!/bin/sh
# herdr plugin action: prints OMP extension integration status
set -eu

package='@the-inconvenience-store/herdr-agent-session-title'

command -v omp >/dev/null 2>&1 || { echo "omp is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

omp plugin list --json | python3 -c '
import json
import sys

package = sys.argv[1]
data = json.load(sys.stdin)
plugin = next((item for item in data.get("npm", []) if item.get("name") == package), None)
if plugin is None:
    print("not installed")
    raise SystemExit(1)
if not plugin.get("enabled"):
    print("installed but disabled: {}".format(package))
    raise SystemExit(1)
print("installed and enabled: {}".format(package))
' "$package"
