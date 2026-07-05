#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sock="$tmp/herdr.sock"
out="$tmp/request.json"
fail() { echo "FAIL: $1" >&2; exit 1; }

# --- case 1: normal hook event reports the title ---
python3 - "$sock" "$out" <<'PY' &
import socket, sys
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
server.settimeout(10)
conn, _ = server.accept()
data = b""
while not data.endswith(b"\n"):
    chunk = conn.recv(4096)
    if not chunk:
        break
    data += chunk
with open(sys.argv[2], "wb") as handle:
    handle.write(data)
conn.sendall(b'{"id":"x","result":{"type":"ok"}}\n')
conn.close()
PY
server_pid=$!

i=0
while [ ! -S "$sock" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
[ -S "$sock" ] || fail "fake server socket did not appear"

printf '{"session_id":"sid-1","transcript_path":"%s","hook_event_name":"Stop"}' \
  "$PWD/tests/fixtures/transcript-custom-title.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$sock" \
  sh scripts/herdr-claude-session-title.sh

wait "$server_pid"

python3 - "$out" <<'PY'
import json, sys
request = json.loads(open(sys.argv[1], "rb").read().decode())
assert request["method"] == "pane.report_metadata", request
params = request["params"]
assert params["pane_id"] == "%42", params
assert params["source"] == "plugin:claude-session-title", params
assert params["agent"] == "claude", params
assert params["title"] == "second-name", params
assert isinstance(params["seq"], int) and params["seq"] > 0, params
print("case 1 (report): OK")
PY

# --- case 2: subagent event must NOT reach the socket ---
sock2="$tmp/herdr2.sock"
python3 - "$sock2" <<'PY' &
import socket, sys
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
server.settimeout(2)
try:
    server.accept()
    raise SystemExit("FAIL: subagent event reached the socket")
except socket.timeout:
    print("case 2 (subagent skip): OK")
PY
server2_pid=$!

i=0
while [ ! -S "$sock2" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done

printf '{"session_id":"sid-1","transcript_path":"%s","hook_event_name":"Stop","agent_id":"agent-xyz"}' \
  "$PWD/tests/fixtures/transcript-custom-title.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$sock2" \
  sh scripts/herdr-claude-session-title.sh

wait "$server2_pid" || fail "subagent event was reported"

# --- case 3: outside herdr the wrapper exits silently ---
printf '{"session_id":"sid-1"}' | sh scripts/herdr-claude-session-title.sh \
  || fail "wrapper must exit 0 outside herdr"

echo "test-socket: OK"
