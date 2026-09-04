#!/bin/sh
# herdr plugin action: removes the linked OMP extension package
set -eu

package='@the-inconvenience-store/herdr-agent-session-title'

command -v omp >/dev/null 2>&1 || { echo "omp is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

if omp plugin list --json | python3 -c '
import json
import sys

package = sys.argv[1]
data = json.load(sys.stdin)
raise SystemExit(0 if any(item.get("name") == package for item in data.get("npm", [])) else 1)
' "$package"
then
  omp plugin uninstall "$package" >/dev/null
fi

echo "uninstalled OMP integration"
