#!/bin/sh
# herdr plugin action: removes the OMP extension package
set -eu

package='@the-inconvenience-store/herdr-agent-session-title'
data_home="${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}"
install_dir="$data_home/herdr-agent-session-title/omp-plugin"

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

if [ -e "$install_dir" ]; then
  [ -f "$install_dir/.herdr-integration" ] || {
    echo "refusing to remove unrecognized OMP package: $install_dir" >&2
    exit 1
  }
  rm -rf "$install_dir"
fi

echo "uninstalled OMP integration"
