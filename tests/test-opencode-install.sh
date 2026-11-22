#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

# A stand-in for the opencode CLI: the installer only reads its version.
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/opencode" <<'SH'
#!/bin/sh
echo "${FAKE_OPENCODE_VERSION:-opencode v2.3.2}"
SH
chmod +x "$tmp/bin/opencode"
original_path=$PATH
export PATH="$tmp/bin:$original_path"
export HOME="$tmp/home"
export HERDR_PLUGIN_ROOT="$PWD"

case_number=0
new_case() {
  case_number=$((case_number + 1))
  export XDG_CONFIG_HOME="$tmp/case$case_number/config"
  config="$XDG_CONFIG_HOME/opencode"
  plugin_dir="$config/herdr-agent-session-title"
  backup="$config/cli.json.bak-herdr-agent-session-title"
  mkdir -p "$XDG_CONFIG_HOME"
}
# assert_json FILE PYTHON_EXPRESSION_OVER_d
assert_json() {
  python3 - "$1" "$2" <<'PY' || fail "unexpected JSON in $1: $2"
import json
import sys

d = json.load(open(sys.argv[1]))
assert eval(sys.argv[2]), d
PY
}
entry='./herdr-agent-session-title'

# 1. Fresh install, status, idempotence, uninstall.
new_case
sh scripts/install-opencode.sh >/dev/null
[ -f "$plugin_dir/.herdr-integration" ] || fail "installer did not mark the owned directory"
cmp -s scripts/herdr-agent-session-title-opencode.mjs "$plugin_dir/tui.js" ||
  fail "tui.js is not the opencode extension"
assert_json "$config/cli.json" "d == {'plugins': ['$entry']}"
[ ! -e "$backup" ] || fail "a backup was made for a file that did not exist"
status_output=$(sh scripts/status-opencode.sh) || fail "status failed after install"
case "$status_output" in
  *"plugin files: installed"*"cli.json entry: registered"*) ;;
  *) fail "status did not report the integration as installed: $status_output" ;;
esac
before=$(cksum < "$config/cli.json")
sh scripts/install-opencode.sh >/dev/null
[ "$before" = "$(cksum < "$config/cli.json")" ] || fail "second install rewrote cli.json"
assert_json "$config/cli.json" "d['plugins'].count('$entry') == 1"
sh scripts/uninstall-opencode.sh >/dev/null
[ ! -e "$plugin_dir" ] || fail "uninstaller left the plugin directory"
assert_json "$config/cli.json" "d == {}"
if sh scripts/status-opencode.sh >/dev/null 2>&1; then
  fail "status succeeded after uninstall"
fi
sh scripts/uninstall-opencode.sh >/dev/null || fail "uninstall is not idempotent"

# 2. Existing cli.json: unrelated settings and plugins survive install and
# uninstall, and the original file is backed up byte for byte.
new_case
mkdir -p "$config"
cat > "$config/cli.json" <<'JSON'
{
  "$schema": "https://example.invalid/cli.json",
  "plugins": [
    "./herdr-opencode",
    { "package": "@acme/opencode-tui", "options": { "compact": true } }
  ],
  "theme": "dark"
}
JSON
cp "$config/cli.json" "$tmp/original-cli.json"
sh scripts/install-opencode.sh >/dev/null
assert_json "$config/cli.json" "d['plugins'] == ['./herdr-opencode', {'package': '@acme/opencode-tui', 'options': {'compact': True}}, '$entry'] and d['theme'] == 'dark' and d['\$schema'].endswith('cli.json')"
cmp -s "$tmp/original-cli.json" "$backup" || fail "backup does not match the original cli.json"
sh scripts/install-opencode.sh >/dev/null
assert_json "$config/cli.json" "d['plugins'].count('$entry') == 1"
sh scripts/uninstall-opencode.sh >/dev/null
assert_json "$config/cli.json" "d['plugins'] == ['./herdr-opencode', {'package': '@acme/opencode-tui', 'options': {'compact': True}}] and d['theme'] == 'dark'"

# 3. Only this plugin registered: uninstall drops the empty plugins array but
# keeps other settings.
new_case
mkdir -p "$config"
printf '{"theme": "dark"}\n' > "$config/cli.json"
sh scripts/install-opencode.sh >/dev/null
sh scripts/uninstall-opencode.sh >/dev/null
assert_json "$config/cli.json" "d == {'theme': 'dark'}"

# 4. A cli.json that cannot be merged safely is refused before anything is
# installed, and is left untouched.
for malformed in '{ "plugins": [' '// comment
{}' '{"plugins": "nope"}' '["not", "an", "object"]'; do
  new_case
  mkdir -p "$config"
  printf '%s\n' "$malformed" > "$config/cli.json"
  cp "$config/cli.json" "$tmp/malformed-cli.json"
  if sh scripts/install-opencode.sh >/dev/null 2>&1; then
    fail "installer accepted a cli.json it cannot merge: $malformed"
  fi
  cmp -s "$tmp/malformed-cli.json" "$config/cli.json" || fail "installer modified a malformed cli.json"
  [ ! -e "$plugin_dir" ] || fail "installer left files behind after refusing cli.json"
  [ ! -e "$backup" ] || fail "installer wrote a backup for a file it refused"
done

# 5. opencode 1.x has no cli.json TUI plugins: refuse instead of installing
# something that never loads. An unparseable version does not block.
new_case
if FAKE_OPENCODE_VERSION="opencode v1.18.31" sh scripts/install-opencode.sh >/dev/null 2>&1; then
  fail "installer accepted opencode 1.x"
fi
[ ! -e "$config" ] || fail "installer wrote files for opencode 1.x"
FAKE_OPENCODE_VERSION="dev-build" sh scripts/install-opencode.sh >/dev/null ||
  fail "installer rejected an unparseable opencode version"
[ -f "$plugin_dir/tui.js" ] || fail "installer skipped an unparseable opencode version"

# 6. A directory this plugin does not own is never replaced or removed.
new_case
mkdir -p "$plugin_dir"
printf 'mine\n' > "$plugin_dir/tui.js"
if sh scripts/install-opencode.sh >/dev/null 2>&1; then
  fail "installer replaced an unrecognized directory"
fi
if sh scripts/uninstall-opencode.sh >/dev/null 2>&1; then
  fail "uninstaller removed an unrecognized directory"
fi
[ "$(cat "$plugin_dir/tui.js")" = "mine" ] || fail "an unrecognized directory was modified"
[ ! -e "$config/cli.json" ] || fail "cli.json was written next to an unrecognized directory"

# 7. Without XDG_CONFIG_HOME the config lives under ~/.config.
new_case
unset XDG_CONFIG_HOME
sh scripts/install-opencode.sh >/dev/null
[ -f "$HOME/.config/opencode/herdr-agent-session-title/tui.js" ] || fail "default config directory was not used"
assert_json "$HOME/.config/opencode/cli.json" "d == {'plugins': ['$entry']}"
sh scripts/uninstall-opencode.sh >/dev/null
[ ! -e "$HOME/.config/opencode/herdr-agent-session-title" ] || fail "default config directory was not cleaned"

# 8. Installing needs the opencode CLI; status and uninstall do not.
new_case
mkdir -p "$tmp/empty"
if PATH="$tmp/empty" /bin/sh scripts/install-opencode.sh >/dev/null 2>&1; then
  fail "installer succeeded without opencode on PATH"
fi
sh scripts/install-opencode.sh >/dev/null
PATH="$original_path" sh scripts/status-opencode.sh >/dev/null || fail "status needs the opencode CLI"
PATH="$original_path" sh scripts/uninstall-opencode.sh >/dev/null || fail "uninstall needs the opencode CLI"

echo "test-opencode-install: OK"
