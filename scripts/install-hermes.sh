#!/bin/sh
# herdr plugin action: links and enables the Hermes session-title plugin
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
plugin_root=$(cd "$plugin_root" && pwd -P)
source_dir="$plugin_root/hermes-plugin"
hermes_home="${HERMES_HOME:-${HOME:?HOME is not set}/.hermes}"
plugins_dir="$hermes_home/plugins"
destination="$plugins_dir/herdr-agent-session-title"
created=0

command -v hermes >/dev/null 2>&1 || { echo "hermes is required" >&2; exit 1; }
[ -f "$source_dir/plugin.yaml" ] && [ -f "$source_dir/__init__.py" ] || {
  echo "Hermes plugin source is incomplete: $source_dir" >&2
  exit 1
}

mkdir -p "$plugins_dir"
if [ -L "$destination" ]; then
  [ "$(readlink "$destination")" = "$source_dir" ] || {
    echo "refusing to replace unrelated Hermes plugin link: $destination" >&2
    exit 1
  }
elif [ -e "$destination" ]; then
  echo "refusing to replace unrelated Hermes plugin path: $destination" >&2
  exit 1
else
  ln -s "$source_dir" "$destination"
  created=1
fi

if ! hermes plugins enable herdr-agent-session-title --no-allow-tool-override >/dev/null; then
  [ "$created" = "0" ] || rm "$destination"
  echo "failed to enable Hermes integration" >&2
  exit 1
fi

echo "installed Hermes integration"
echo "note: already-running Hermes processes load the plugin on restart"
