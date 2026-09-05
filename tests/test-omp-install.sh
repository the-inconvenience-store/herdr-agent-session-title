#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if ! command -v omp >/dev/null 2>&1; then
  echo "test-omp-install: SKIP (omp is required)"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/xdg/config"
export XDG_DATA_HOME="$tmp/xdg/data"
export XDG_STATE_HOME="$tmp/xdg/state"
export XDG_CACHE_HOME="$tmp/xdg/cache"
export HERDR_PLUGIN_ROOT="$PWD"
omp_source="$XDG_DATA_HOME/herdr-agent-session-title/omp-plugin"
mkdir -p "$HOME" "$tmp/other-plugin"

cat > "$tmp/other-plugin/package.json" <<'JSON'
{
  "name": "unrelated-omp-plugin",
  "version": "1.0.0",
  "type": "module",
  "omp": {
    "extensions": ["./index.mjs"]
  }
}
JSON
cat > "$tmp/other-plugin/index.mjs" <<'JS'
export default function unrelatedPlugin() {}
JS

omp plugin link "$tmp/other-plugin" >/dev/null
sh scripts/install-omp.sh >/dev/null
sh scripts/install-omp.sh >/dev/null
[ -f "$omp_source/.herdr-integration" ] || fail "installer did not create the owned OMP package"
[ -f "$omp_source/scripts/herdr-agent-session-title-omp.mjs" ] || fail "OMP extension was not copied"

status_output=$(sh scripts/status-omp.sh)
case "$status_output" in
  *"installed and enabled: @the-inconvenience-store/herdr-agent-session-title"*) ;;
  *) fail "status did not report the OMP integration as enabled: $status_output" ;;
esac


plugin_json=$(omp plugin list --json)
OMP_PLUGIN_LIST_JSON="$plugin_json" python3 - "$omp_source" <<'PY'
import json
import os
import sys

plugins = {item["name"]: item for item in json.loads(os.environ["OMP_PLUGIN_LIST_JSON"])["npm"]}
ours = plugins["@the-inconvenience-store/herdr-agent-session-title"]
assert ours["enabled"] is True, ours
assert os.path.realpath(ours["path"]) == os.path.realpath(sys.argv[1]), ours
assert plugins["unrelated-omp-plugin"]["enabled"] is True, plugins
PY

omp plugin disable @the-inconvenience-store/herdr-agent-session-title >/dev/null
if sh scripts/status-omp.sh >/dev/null 2>&1; then
  fail "status succeeded while the OMP integration was disabled"
fi
omp plugin enable @the-inconvenience-store/herdr-agent-session-title >/dev/null

sh scripts/uninstall-omp.sh >/dev/null
sh scripts/uninstall-omp.sh >/dev/null
[ ! -e "$omp_source" ] || fail "uninstaller left the owned OMP package"

plugin_json=$(omp plugin list --json)
OMP_PLUGIN_LIST_JSON="$plugin_json" python3 - <<'PY'
import json
import os

plugins = {item["name"]: item for item in json.loads(os.environ["OMP_PLUGIN_LIST_JSON"])["npm"]}
assert "@the-inconvenience-store/herdr-agent-session-title" not in plugins, plugins
assert plugins["unrelated-omp-plugin"]["enabled"] is True, plugins
PY

echo "test-omp-install: OK"
