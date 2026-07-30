#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

export HOME="$tmp"
export CODEX_HOME="$tmp/.codex"
export HERDR_PLUGIN_ROOT="$PWD"
mkdir -p "$CODEX_HOME"

# Preserve and chain an existing notification command.
existing_notifier="$tmp/existing-notifier.sh"
cat > "$existing_notifier" <<'SH'
#!/bin/sh
printf '%s' "$1" > "$CHAIN_OUTPUT"
SH
chmod +x "$existing_notifier"
export CHAIN_OUTPUT="$tmp/chained-notification.json"

cat > "$CODEX_HOME/config.toml" <<TOML
model = "gpt-test"
notify = [
  "sh",
  "$existing_notifier",
]

[tui]
animations = false
TOML

sh scripts/install-codex.sh >/dev/null
sh scripts/install-codex.sh >/dev/null

python3 - "$CODEX_HOME/config.toml" "$CODEX_HOME/herdr-session-title-notify-state.json" "$existing_notifier" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = handle.read()
assert 'model = "gpt-test"' in config, config
assert "animations = false" in config, config
assert 'notify = ["python3", ' in config, config
assert "herdr-codex-session-title.py" in config, config

with open(sys.argv[2], encoding="utf-8") as handle:
    state = json.load(handle)
assert state["previous_notify"] == ["sh", sys.argv[3]], state
print("Codex install idempotency and preservation: OK")
PY

[ -x "$CODEX_HOME/herdr-codex-session-title.py" ] ||
  fail "Codex callback copy missing"
[ -f "$CODEX_HOME/config.toml.bak-codex-session-title" ] ||
  fail "Codex config backup missing"

# The wrapper must forward every event to a pre-existing notifier, even when
# the event is irrelevant to herdr.
raw_notification='{"type":"unsupported","value":"preserved"}'
python3 "$CODEX_HOME/herdr-codex-session-title.py" "$raw_notification"
attempts=0
while [ ! -f "$CHAIN_OUTPUT" ]; do
  attempts=$((attempts + 1))
  [ "$attempts" -lt 100 ] || fail "existing Codex notifier was not chained"
  sleep 0.01
done
[ "$(cat "$CHAIN_OUTPUT")" = "$raw_notification" ] ||
  fail "existing Codex notifier received the wrong payload"
echo "Codex existing notifier chaining: OK"

# Create a representative Codex state database.
python3 - "$CODEX_HOME/state_5.sqlite" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute(
    "CREATE TABLE threads ("
    "id TEXT PRIMARY KEY, name TEXT, title TEXT, first_user_message TEXT)"
)
connection.executemany(
    "INSERT INTO threads VALUES (?, ?, ?, ?)",
    [
        ("named-thread", "Explicit rename", "Initial extracted title", "Initial prompt"),
        ("unnamed-thread", None, "Extracted first prompt", "Initial prompt"),
    ],
)
connection.commit()
connection.close()
PY

run_socket_case() {
  thread_id=$1
  expected=$2
  socket_path="$tmp/$thread_id.sock"
  output_path="$tmp/$thread_id.json"

  python3 - "$socket_path" "$output_path" <<'PY' &
import json
import os
import socket
import sys

socket_path, output_path = sys.argv[1:]
try:
    os.unlink(socket_path)
except FileNotFoundError:
    pass
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(1)
connection, _ = server.accept()
data = b""
while not data.endswith(b"\n"):
    data += connection.recv(65536)
connection.close()
server.close()
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(json.loads(data), handle)
PY
  server_pid=$!

  attempts=0
  while [ ! -S "$socket_path" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || fail "socket server did not start"
    sleep 0.01
  done

  HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH="$socket_path" \
    python3 scripts/herdr-codex-session-title.py \
    "{\"type\":\"agent-turn-complete\",\"thread-id\":\"$thread_id\",\"input-messages\":[\"Notification fallback\"]}"
  wait "$server_pid"

  python3 - "$output_path" "$expected" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    request = json.load(handle)
params = request["params"]
assert request["method"] == "pane.report_metadata", request
assert params["source"] == "plugin:codex-session-title", params
assert params["agent"] == "codex", params
assert params["title"] == sys.argv[2], params
PY
}

run_socket_case named-thread "Explicit rename"
run_socket_case unnamed-thread "Extracted first prompt"
echo "Codex title priority: OK"

sh scripts/uninstall-codex.sh >/dev/null

python3 - "$CODEX_HOME/config.toml" "$existing_notifier" <<'PY'
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = handle.read()
expected = 'notify = [\n  "sh",\n  "{}",\n]'.format(sys.argv[2])
assert expected in config, config
assert 'model = "gpt-test"' in config, config
assert "animations = false" in config, config
print("Codex uninstall restoration: OK")
PY

[ ! -e "$CODEX_HOME/herdr-codex-session-title.py" ] ||
  fail "Codex callback copy not removed"
[ ! -e "$CODEX_HOME/herdr-session-title-notify-state.json" ] ||
  fail "Codex integration state not removed"

echo "test-codex-notify: OK"
