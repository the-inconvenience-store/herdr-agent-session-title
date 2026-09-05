#!/bin/sh
# herdr plugin action: prints OMP extension integration status
set -eu

package='@the-inconvenience-store/herdr-agent-session-title'
data_home="${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}"
install_dir="$data_home/herdr-agent-session-title/omp-plugin"

command -v omp >/dev/null 2>&1 || { echo "omp is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

[ -f "$install_dir/.herdr-integration" ] || {
  echo "not installed"
  exit 1
}

omp plugin list --json | python3 -c '
import json
import os
import sys

package, expected = sys.argv[1:]
data = json.load(sys.stdin)
plugin = next((item for item in data.get("npm", []) if item.get("name") == package), None)
if plugin is None:
    print("not installed")
    raise SystemExit(1)
if not plugin.get("enabled"):
    print("installed but disabled: {}".format(package))
    raise SystemExit(1)
if os.path.realpath(plugin.get("path", "")) != os.path.realpath(expected):
    print("installed from an unexpected path: {}".format(plugin.get("path", "")))
    raise SystemExit(1)
print("installed and enabled: {}".format(package))
' "$package" "$install_dir"
