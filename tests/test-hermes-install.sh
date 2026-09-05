#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

export HOME="$tmp/home"
export HERMES_HOME="$tmp/hermes-home"
export HERDR_PLUGIN_ROOT="$PWD"
export FAKE_HERMES_LOG="$tmp/hermes.log"
mkdir -p "$HOME" "$HERMES_HOME" "$tmp/bin"

cat > "$tmp/bin/hermes" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${FAKE_HERMES_LOG:?}"
state="${HERMES_HOME:?}/fake-plugin-state"
case "$1:$2" in
  plugins:enable)
    if [ "${FAKE_HERMES_FAIL_ENABLE:-0}" = "1" ]; then
      exit 1
    fi
    echo enabled > "$state"
    ;;
  plugins:disable)
    echo disabled > "$state"
    ;;
  plugins:list)
    status=disabled
    [ ! -f "$state" ] || status=$(cat "$state")
    if [ -L "$HERMES_HOME/plugins/herdr-agent-session-title" ]; then
      printf '[{"name":"unrelated","status":"enabled","source":"user"},{"name":"herdr-agent-session-title","status":"%s","source":"user"}]\n' "$status"
    else
      printf '[{"name":"unrelated","status":"enabled","source":"user"}]\n'
    fi
    ;;
  *)
    echo "unexpected hermes invocation: $*" >&2
    exit 1
    ;;
esac
SH
chmod +x "$tmp/bin/hermes"
export PATH="$tmp/bin:$PATH"

destination="$HERMES_HOME/plugins/herdr-agent-session-title"

sh scripts/install-hermes.sh >/dev/null
sh scripts/install-hermes.sh >/dev/null
[ -L "$destination" ] || fail "installer did not create a plugin link"
[ "$(readlink "$destination")" = "$PWD/hermes-plugin" ] || fail "plugin link target is wrong"

status_output=$(sh scripts/status-hermes.sh)
case "$status_output" in
  *"installed and enabled: herdr-agent-session-title"*) ;;
  *) fail "status did not report the Hermes integration as enabled: $status_output" ;;
esac

python3 - "$FAKE_HERMES_LOG" <<'PY'
import pathlib
import sys

calls = pathlib.Path(sys.argv[1]).read_text().splitlines()
enable = [call for call in calls if call.startswith("plugins enable ")]
assert enable, calls
assert all("--no-allow-tool-override" in call for call in enable), calls
PY

hermes plugins disable herdr-agent-session-title >/dev/null
if status_output=$(sh scripts/status-hermes.sh 2>&1); then
  fail "status succeeded while the Hermes integration was disabled"
fi
case "$status_output" in
  *"installed but disabled: herdr-agent-session-title"*) ;;
  *) fail "disabled status was unclear: $status_output" ;;
esac
hermes plugins enable herdr-agent-session-title --no-allow-tool-override >/dev/null

sh scripts/uninstall-hermes.sh >/dev/null
sh scripts/uninstall-hermes.sh >/dev/null
[ ! -e "$destination" ] && [ ! -L "$destination" ] || fail "uninstaller left the plugin link"

mkdir -p "$destination"
printf 'foreign\n' > "$destination/owner"
if sh scripts/install-hermes.sh >/dev/null 2>&1; then
  fail "installer replaced a foreign plugin path"
fi
if sh scripts/uninstall-hermes.sh >/dev/null 2>&1; then
  fail "uninstaller removed a foreign plugin path"
fi
[ "$(cat "$destination/owner")" = "foreign" ] || fail "foreign plugin contents changed"
rm -rf "$destination"

if FAKE_HERMES_FAIL_ENABLE=1 sh scripts/install-hermes.sh >/dev/null 2>&1; then
  fail "installer succeeded when Hermes enable failed"
fi
[ ! -e "$destination" ] && [ ! -L "$destination" ] || fail "failed install left a plugin link"

printf 'test-hermes-install: OK\n'
