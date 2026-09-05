#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
assert_log() {
  actual=$(cat "$FAKE_INTEGRATION_LOG")
  expected=$(printf '%s\n' "$@")
  [ "$actual" = "$expected" ] || fail "unexpected dispatch log: $actual"
}

python_bin=$(command -v python3)
export HOME="$tmp/home"
export HERDR_PLUGIN_ROOT="$tmp/plugin"
export FAKE_INTEGRATION_LOG="$tmp/integrations.log"
mkdir -p "$HOME" "$tmp/plugin/scripts" "$tmp/bin"

cat > "$tmp/plugin/scripts/fake-action" <<'SH'
#!/bin/sh
set -eu
case "$(basename "$0")" in
  install-claude.sh) key=install:claude ;;
  status-claude.sh) key=status:claude ;;
  uninstall-claude.sh) key=uninstall:claude ;;
  install-codex.sh) key=install:codex ;;
  status-codex.sh) key=status:codex ;;
  uninstall-codex.sh) key=uninstall:codex ;;
  install-omp.sh) key=install:omp ;;
  status-omp.sh) key=status:omp ;;
  uninstall-omp.sh) key=uninstall:omp ;;
  install-hermes.sh) key=install:hermes ;;
  status-hermes.sh) key=status:hermes ;;
  uninstall-hermes.sh) key=uninstall:hermes ;;
  *) exit 2 ;;
esac
printf '%s\n' "$key" >> "${FAKE_INTEGRATION_LOG:?}"
[ "${FAKE_INTEGRATION_FAIL:-}" != "$key" ]
SH
chmod +x "$tmp/plugin/scripts/fake-action"
for name in \
  install-claude.sh status-claude.sh uninstall-claude.sh \
  install-codex.sh status-codex.sh uninstall-codex.sh \
  install-omp.sh status-omp.sh uninstall-omp.sh \
  install-hermes.sh status-hermes.sh uninstall-hermes.sh
do
  ln -s fake-action "$tmp/plugin/scripts/$name"
done

cat > "$tmp/bin/claude" <<'SH'
#!/bin/sh
exit 0
SH
cp "$tmp/bin/claude" "$tmp/bin/codex"
chmod +x "$tmp/bin/claude" "$tmp/bin/codex"
export PATH="$tmp/bin:/usr/bin:/bin"

: > "$FAKE_INTEGRATION_LOG"
sh scripts/integrations.sh install >/dev/null
assert_log install:claude install:codex

: > "$FAKE_INTEGRATION_LOG"
sh scripts/integrations.sh status >/dev/null
assert_log status:claude status:codex

cp "$tmp/bin/claude" "$tmp/bin/omp"
cp "$tmp/bin/claude" "$tmp/bin/hermes"
chmod +x "$tmp/bin/omp" "$tmp/bin/hermes"
: > "$FAKE_INTEGRATION_LOG"
sh scripts/integrations.sh install hermes omp codex codex >/dev/null
assert_log install:hermes install:omp install:codex

: > "$FAKE_INTEGRATION_LOG"
if sh scripts/integrations.sh install unknown >/dev/null 2>&1; then
  fail "dispatcher accepted an unknown agent"
fi
assert_log

: > "$FAKE_INTEGRATION_LOG"
if FAKE_INTEGRATION_FAIL=install:codex \
  sh scripts/integrations.sh install claude codex hermes >/dev/null 2>&1
then
  fail "dispatcher hid an integration failure"
fi
assert_log install:claude install:codex install:hermes

rm "$tmp/bin/claude" "$tmp/bin/codex" "$tmp/bin/omp" "$tmp/bin/hermes"
mkdir -p "$HOME/.claude"
printf 'callback\n' > "$HOME/.claude/herdr-agent-session-title-claude.py"
: > "$FAKE_INTEGRATION_LOG"
sh scripts/integrations.sh status >/dev/null
assert_log status:claude

"$python_bin" - <<'PY'
import json
import pathlib
import tomllib

manifest = tomllib.loads(pathlib.Path("herdr-plugin.toml").read_text())
assert manifest["build"] == [{"command": ["sh", "scripts/integrations.sh", "install"]}]
actions = {entry["id"]: entry["command"] for entry in manifest["actions"]}
assert actions == {
    "install": ["sh", "scripts/integrations.sh", "install"],
    "status": ["sh", "scripts/integrations.sh", "status"],
    "uninstall": ["sh", "scripts/integrations.sh", "uninstall"],
}, actions
assert json.loads(pathlib.Path("package.json").read_text())["version"] == "0.10.0"
assert 'version: "0.10.0"' in pathlib.Path("hermes-plugin/plugin.yaml").read_text()
PY

printf 'test-integrations: OK\n'
