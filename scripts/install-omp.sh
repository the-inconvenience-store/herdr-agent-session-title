#!/bin/sh
# herdr plugin action: installs a self-contained OMP extension package
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
data_home="${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}"
install_dir="$data_home/herdr-agent-session-title/omp-plugin"
staging="$install_dir.tmp.$$"
package='@the-inconvenience-store/herdr-agent-session-title'

command -v omp >/dev/null 2>&1 || { echo "omp is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

if [ -e "$install_dir" ]; then
  python3 - "$install_dir/package.json" "$package" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, ValueError) as error:
    raise SystemExit("refusing to replace unrecognized OMP package: {}".format(error))
if manifest.get("name") != sys.argv[2]:
    raise SystemExit("refusing to replace unrelated OMP package")
PY
fi

rm -rf "$staging"
trap 'rm -rf "$staging"' EXIT HUP INT TERM
mkdir -p "$staging/scripts"
cp "$plugin_root/package.json" "$staging/package.json"
cp "$plugin_root/scripts/herdr-agent-session-title-omp.mjs" "$staging/scripts/"
printf '%s\n' 'HERDR_INTEGRATION_ID=omp-session-title' > "$staging/.herdr-integration"
if [ -e "$install_dir" ]; then
  rm -rf "$install_dir"
fi
mkdir -p "$(dirname "$install_dir")"
mv "$staging" "$install_dir"
trap - EXIT HUP INT TERM

omp plugin link "$install_dir" >/dev/null

echo "installed OMP integration"
echo "note: already-running OMP sessions load the extension on restart"
