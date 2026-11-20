#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
unset CURSOR_CONFIG_DIR 2>/dev/null || true
fail() { echo "FAIL: $1" >&2; exit 1; }

chats="$HOME/.cursor/chats"
mkdir -p "$chats"

sock="$tmp/herdr.sock"
requests="$tmp/requests.jsonl"
: > "$requests"

python3 - "$sock" "$requests" <<'PY' &
import socket
import sys

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(8)
server.settimeout(30)
with open(sys.argv[2], "ab", buffering=0) as out:
    try:
        while True:
            connection, _ = server.accept()
            data = b""
            while not data.endswith(b"\n"):
                chunk = connection.recv(4096)
                if not chunk:
                    break
                data += chunk
            out.write(data if data.endswith(b"\n") else data + b"\n")
            connection.sendall(b'{"id":"x","result":{"type":"ok"}}\n')
            connection.close()
    except socket.timeout:
        pass
PY
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -rf "$tmp"' EXIT

attempts=0
while [ ! -S "$sock" ]; do
  attempts=$((attempts + 1))
  [ "$attempts" -lt 200 ] || fail "fake server socket did not appear"
  sleep 0.01
done

write_meta() {
  session_id=$1
  title=$2
  is_subagent=${3:-false}
  mkdir -p "$chats/workspacehash/$session_id"
  python3 - "$chats/workspacehash/$session_id/meta.json" "$title" "$is_subagent" <<'PY'
import json
import sys

meta = {
    "schemaVersion": 1,
    "createdAtMs": 1795028028036,
    "hasConversation": True,
    "title": sys.argv[2],
    "updatedAtMs": 1795187030392,
    "cwd": "/workspace",
}
if sys.argv[3] == "true":
    meta.pop("title")
    meta["isSubagent"] = True
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(meta, handle)
PY
}

run_hook() {
  event=$1
  session_field=$2
  session_id=$3
  herdr_env=${4:-1}
  payload=$(python3 - "$event" "$session_field" "$session_id" <<'PY'
import json
import sys

print(json.dumps({
    "hook_event_name": sys.argv[1],
    sys.argv[2]: sys.argv[3],
    "conversation_id": sys.argv[3],
    "workspace_roots": ["/workspace"],
}))
PY
)
  printf '%s' "$payload" |
    HERDR_ENV="$herdr_env" HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$sock" \
    python3 scripts/herdr-agent-session-title-cursor.py
}

request_count() {
  wc -l < "$requests" | tr -d ' '
}

wait_for_count() {
  wanted=$1
  attempts=0
  while [ "$(request_count)" -lt "$wanted" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || fail "expected $wanted rename request(s), got $(request_count)"
    sleep 0.1
  done
}

expect_rename() {
  python3 - "$requests" "$1" "$2" <<'PY'
import json
import sys

lines = [line for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
request = json.loads(lines[-1])
assert request["method"] == "agent.rename", request
assert request["params"] == {"target": "%42", "name": sys.argv[3]}, request
assert request["id"].startswith("plugin:herdr-agent-session-title:"), request
print("rename request for {}: OK".format(sys.argv[2]))
PY
}

# 1. A title that already exists renames on sessionStart.
write_meta "11111111-1111-4111-8111-111111111111" "Hello Reply"
run_hook sessionStart session_id "11111111-1111-4111-8111-111111111111"
wait_for_count 1
expect_rename "sessionStart title" "hello-reply"

# 2. The placeholder name Cursor uses before generating a title is ignored.
write_meta "22222222-2222-4222-8222-222222222222" "New Agent"
run_hook sessionStart session_id "22222222-2222-4222-8222-222222222222"
sleep 1
[ "$(request_count)" = "1" ] || fail "placeholder title renamed the agent"

# 3. Subagent chats never rename the containing pane.
write_meta "33333333-3333-4333-8333-333333333333" "" true
run_hook sessionStart conversation_id "33333333-3333-4333-8333-333333333333"
sleep 1
[ "$(request_count)" = "1" ] || fail "subagent chat renamed the agent"

# 4. Outside herdr the callback is silent.
run_hook sessionStart session_id "11111111-1111-4111-8111-111111111111" 0
sleep 1
[ "$(request_count)" = "1" ] || fail "callback acted outside herdr"

# 5. A slow generated title is picked up by the stop follow-up.
write_meta "44444444-4444-4444-8444-444444444444" ""
run_hook stop session_id "44444444-4444-4444-8444-444444444444"
sleep 0.3
write_meta "44444444-4444-4444-8444-444444444444" "Filter Outdated Events"
wait_for_count 2
expect_rename "stop follow-up" "filter-outdated-events"

# 6. The extract entry point resolves titles for debugging and tests.
out=$(python3 scripts/herdr-agent-session-title-cursor.py extract \
  "11111111-1111-4111-8111-111111111111")
[ "$out" = "Hello Reply" ] || fail "extract returned: $out"

kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
echo "test-cursor-hook: OK"
