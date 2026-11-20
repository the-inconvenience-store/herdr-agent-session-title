#!/usr/bin/env python3
"""Report a Cursor Agent CLI chat title to herdr.

Cursor invokes this program from its user hooks (``~/.cursor/hooks.json``) for
``sessionStart`` and ``stop``. Cursor's hook input carries no title, so the
program reads the title Cursor persists for the session in its chat sidecar:

    <cursor config dir>/chats/<workspace hash>/<session id>/meta.json

Titles are generated asynchronously after the first turn. When ``stop`` runs
before the title is persisted, the program starts a short detached follow-up
instead of blocking the hook.
"""

import glob
import json
import os
import random
import re
import socket
import subprocess
import sys
import time

SOURCE = "plugin:herdr-agent-session-title"
MAX_TITLE_CHARS = 120
HOOK_EVENTS = ("sessionStart", "stop")
FOLLOW_UP_SECONDS = 15.0
FOLLOW_UP_INTERVAL = 0.5
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
# Cursor's default chat name before it generates a title.
PLACEHOLDER_TITLES = {"new agent"}


def sanitize(title):
    if not isinstance(title, str):
        return None
    cleaned = "".join(
        " " if (ch < " " or ch == "\x7f" or "\x80" <= ch <= "\x9f") else ch
        for ch in title
    )
    cleaned = " ".join(cleaned.split())
    if not cleaned:
        return None
    return cleaned[:MAX_TITLE_CHARS]


def normalize_agent_name(title):
    title = sanitize(title)
    if not title:
        return None
    normalized = title.lower()
    normalized = re.sub(r"[^a-z0-9_-]+", "-", normalized)
    normalized = re.sub(r"[-_]+", "-", normalized).strip("-_")
    normalized = normalized[:32].rstrip("-_")
    if not normalized or not normalized[0].isalpha():
        normalized = "session-" + normalized
        normalized = normalized[:32].rstrip("-_")
    return normalized or None


def cursor_config_dir():
    configured = os.environ.get("CURSOR_CONFIG_DIR", "").strip()
    if configured:
        return configured
    xdg_config_home = os.environ.get("XDG_CONFIG_HOME", "").strip()
    if xdg_config_home:
        return os.path.join(xdg_config_home, "cursor")
    return os.path.join(os.path.expanduser("~"), ".cursor")


def title_from_meta(home, session_id):
    if not isinstance(session_id, str) or not SESSION_ID_RE.match(session_id):
        return None
    pattern = os.path.join(home, "chats", "*", session_id, "meta.json")
    for meta_path in glob.glob(pattern):
        try:
            with open(meta_path, encoding="utf-8") as handle:
                meta = json.load(handle)
        except (OSError, ValueError):
            continue
        # Subagents get their own chat sidecar and must not rename the pane.
        if not isinstance(meta, dict) or meta.get("isSubagent"):
            continue
        title = sanitize(meta.get("title"))
        if title and title.lower() not in PLACEHOLDER_TITLES:
            return title
    return None


def rename_agent(pane_id, socket_path, title):
    name = normalize_agent_name(title)
    if not name:
        return
    request = {
        "id": "{}:{}:{:06d}".format(
            SOURCE, int(time.time() * 1000), random.randrange(1_000_000)
        ),
        "method": "agent.rename",
        "params": {
            "target": pane_id,
            "name": name,
        },
    }
    payload = (json.dumps(request, separators=(",", ":")) + "\n").encode()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    try:
        client.connect(socket_path)
        client.sendall(payload)
        # Herdr sends one JSON response per request. Keep the connection open
        # long enough to receive it; closing immediately can make response
        # delivery fail and causes the server to report the mutation as an
        # errored API request.
        response = b""
        while not response.endswith(b"\n"):
            chunk = client.recv(4096)
            if not chunk:
                break
            response += chunk
    finally:
        client.close()


def start_follow_up(home, session_id, pane_id, socket_path):
    try:
        subprocess.Popen(
            [
                sys.executable,
                os.path.abspath(__file__),
                "follow-up",
                home,
                session_id,
                pane_id,
                socket_path,
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def follow_up(home, session_id, pane_id, socket_path):
    deadline = time.time() + FOLLOW_UP_SECONDS
    while time.time() < deadline:
        title = title_from_meta(home, session_id)
        if title:
            rename_agent(pane_id, socket_path, title)
            return
        time.sleep(FOLLOW_UP_INTERVAL)


def handle(raw_input):
    try:
        payload = json.loads(raw_input)
    except ValueError:
        return
    if not isinstance(payload, dict):
        return
    if os.environ.get("HERDR_ENV") != "1":
        return
    pane_id = os.environ.get("HERDR_PANE_ID")
    socket_path = os.environ.get("HERDR_SOCKET_PATH")
    if not isinstance(pane_id, str) or not isinstance(socket_path, str):
        return
    if not pane_id or not socket_path:
        return
    event = payload.get("hook_event_name") or payload.get("hookEventName")
    if event not in HOOK_EVENTS:
        return
    session_id = payload.get("session_id") or payload.get("conversation_id")
    if not isinstance(session_id, str) or not session_id:
        return
    home = cursor_config_dir()
    title = title_from_meta(home, session_id)
    if title:
        rename_agent(pane_id, socket_path, title)
        return
    # Only the end of a turn can be followed by a newly generated title.
    if event == "stop":
        start_follow_up(home, session_id, pane_id, socket_path)


def main(argv):
    if len(argv) == 1:
        try:
            handle(sys.stdin.read())
        except Exception:
            # A hook must never disturb Cursor.
            pass
        return 0
    if len(argv) == 3 and argv[1] == "extract":
        title = title_from_meta(cursor_config_dir(), argv[2])
        if not title:
            return 1
        print(title)
        return 0
    if len(argv) == 6 and argv[1] == "follow-up":
        follow_up(argv[2], argv[3], argv[4], argv[5])
        return 0
    print(
        "usage: herdr-agent-session-title-cursor.py "
        "| extract <session_id> | follow-up <home> <session_id> <pane> <socket>",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
