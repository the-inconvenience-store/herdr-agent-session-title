#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

export HOME="$tmp"
export CLAUDE_CONFIG_DIR="$tmp/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR"

# Preserve an existing status line and verify that its output is relayed.
cat > "$tmp/previous-statusline.sh" <<'SH'
#!/bin/sh
input=$(cat)
printf 'existing:%s' "$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session_id"])')"
SH
chmod +x "$tmp/previous-statusline.sh"
python3 - "$CLAUDE_CONFIG_DIR/herdr-session-title-statusline-state.json" "$tmp/previous-statusline.sh" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "previous_status_line": {
                "type": "command",
                "command": "sh '{}'".format(sys.argv[2]),
            }
        },
        handle,
    )
PY

run_socket_case() {
  case_name=$1
  session_name=$2
  transcript=$3
  expected=$4
  sock="$tmp/$case_name.sock"
  out="$tmp/$case_name.json"

  python3 - "$sock" "$out" <<'PY' &
import socket
import sys

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
server.settimeout(10)
connection, _ = server.accept()
data = b""
while not data.endswith(b"\n"):
    chunk = connection.recv(4096)
    if not chunk:
        break
    data += chunk
with open(sys.argv[2], "wb") as handle:
    handle.write(data)
connection.sendall(b'{"id":"x","result":{"type":"ok"}}\n')
connection.close()
server.close()
PY
  server_pid=$!

  attempts=0
  while [ ! -S "$sock" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || fail "fake server socket did not appear"
    sleep 0.01
  done

  status_input=$(python3 - "$session_name" "$transcript" <<'PY'
import json
import sys

value = {
    "session_id": "sid-status",
    "transcript_path": sys.argv[2],
}
if sys.argv[1]:
    value["session_name"] = sys.argv[1]
print(json.dumps(value))
PY
)
  status_output=$(
    printf '%s' "$status_input" |
      HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$sock" \
      python3 scripts/herdr-claude-session-title.py
  )
  [ "$status_output" = "existing:sid-status" ] ||
    fail "existing status-line output was not preserved: $status_output"
  wait "$server_pid"

  python3 - "$out" "$expected" <<'PY'
import json
import sys

request = json.loads(open(sys.argv[1], "rb").read().decode())
assert request["method"] == "pane.report_metadata", request
params = request["params"]
assert params["pane_id"] == "%42", params
assert params["source"] == "plugin:claude-session-title", params
assert params["agent"] == "claude", params
assert params["title"] == sys.argv[2], params
assert isinstance(params["seq"], int) and params["seq"] > 0, params
PY
}

run_socket_case \
  explicit-name \
  "Status input rename" \
  "$PWD/tests/fixtures/transcript-ai-title.jsonl" \
  "Status input rename"
echo "case 1 (session_name priority and relay): OK"

run_socket_case \
  transcript-title \
  "" \
  "$PWD/tests/fixtures/transcript-ai-title.jsonl" \
  "auto generated name v2"
echo "case 2 (transcript AI title fallback): OK"

# Outside herdr, the wrapper still relays the existing status line.
outside_output=$(
  printf '{"session_id":"outside"}' |
    python3 scripts/herdr-claude-session-title.py
)
[ "$outside_output" = "existing:outside" ] ||
  fail "wrapper did not relay the existing status line outside herdr"

echo "test-socket: OK"
