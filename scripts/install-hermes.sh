#!/bin/sh
# herdr plugin action: copies and enables the Hermes session-title plugin
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
source_dir="$plugin_root/hermes-plugin"
hermes_home="${HERMES_HOME:-${HOME:?HOME is not set}/.hermes}"
plugins_dir="$hermes_home/plugins"
destination="$plugins_dir/herdr-agent-session-title"
staging="$plugins_dir/.herdr-agent-session-title.tmp.$$"
backup="$plugins_dir/.herdr-agent-session-title.backup.$$"

command -v hermes >/dev/null 2>&1 || { echo "hermes is required" >&2; exit 1; }
[ -f "$source_dir/plugin.yaml" ] &&
  [ -f "$source_dir/__init__.py" ] &&
  [ -f "$source_dir/.herdr-integration" ] || {
    echo "Hermes plugin source is incomplete: $source_dir" >&2
    exit 1
  }

mkdir -p "$plugins_dir"
if [ -e "$destination" ] || [ -L "$destination" ]; then
  [ -f "$destination/.herdr-integration" ] || {
    echo "refusing to replace unrelated Hermes plugin path: $destination" >&2
    exit 1
  }
fi

activated=0
rollback() {
  rm -rf "$staging"
  if [ "$activated" = "1" ]; then
    rm -rf "$destination"
  fi
  if [ -e "$backup" ] || [ -L "$backup" ]; then
    mv "$backup" "$destination"
  fi
}
trap rollback EXIT HUP INT TERM

rm -rf "$staging" "$backup"
mkdir -p "$staging"
cp "$source_dir/plugin.yaml" "$staging/plugin.yaml"
cp "$source_dir/__init__.py" "$staging/__init__.py"
cp "$source_dir/.herdr-integration" "$staging/.herdr-integration"
if [ -e "$destination" ] || [ -L "$destination" ]; then
  mv "$destination" "$backup"
fi
mv "$staging" "$destination"
activated=1

if ! hermes plugins enable herdr-agent-session-title --no-allow-tool-override >/dev/null; then
  echo "failed to enable Hermes integration" >&2
  exit 1
fi

rm -rf "$backup"
trap - EXIT HUP INT TERM
echo "installed Hermes integration"
echo "note: already-running Hermes processes load the plugin on restart"
