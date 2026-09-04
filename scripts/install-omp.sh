#!/bin/sh
# herdr plugin action: links the OMP extension package
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"

command -v omp >/dev/null 2>&1 || { echo "omp is required" >&2; exit 1; }

omp plugin link "$plugin_root" >/dev/null

echo "installed OMP integration"
echo "note: already-running OMP sessions load the extension on restart"
