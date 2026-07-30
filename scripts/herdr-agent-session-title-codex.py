#!/usr/bin/env python3
"""Report a Codex thread name (or extracted first-prompt title) to herdr.

Codex invokes this program through its top-level `notify` setting. The
notification callback receives one JSON argument for `agent-turn-complete`.
"""

import glob
import json
import os
import random
import socket
import sqlite3
import subprocess
import sys
import time

SOURCE = "plugin:herdr-agent-session-title"
MAX_TITLE_CHARS = 120
STATE_FILE = "herdr-session-title-notify-state.json"


def sanitize(title):
    if not isinstance(title, str):
        return None
    cleaned = "".join(
        ch if ch >= " " and ch not in ("\x7f", "\x9b") else " "
        for ch in title
    )
    cleaned = " ".join(cleaned.split())
    if not cleaned:
        return None
    return cleaned[:MAX_TITLE_CHARS]


def codex_home():
    return os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")


def database_paths(home):
    paths = glob.glob(os.path.join(home, "state_*.sqlite"))
    paths.sort(key=lambda path: os.path.getmtime(path), reverse=True)
    return paths


def title_from_session_index(home, thread_id):
    index_path = os.path.join(home, "session_index.jsonl")
    title = None
    try:
        with open(index_path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if thread_id not in line or '"thread_name"' not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict) or record.get("id") != thread_id:
                    continue
                title = sanitize(record.get("thread_name"))
    except OSError:
        return None
    return title


def titles_from_database(home, thread_id):
    for path in database_paths(home):
        try:
            connection = sqlite3.connect(
                "file:{}?mode=ro".format(path), uri=True, timeout=0.2
            )
            try:
                columns = {
                    row[1]
                    for row in connection.execute("PRAGMA table_info(threads)")
                }
                wanted = [
                    column
                    for column in ("name", "title", "first_user_message")
                    if column in columns
                ]
                if not wanted or "id" not in columns:
                    continue
                query = "SELECT {} FROM threads WHERE id = ?".format(
                    ", ".join(wanted)
                )
                row = connection.execute(query, (thread_id,)).fetchone()
                if row:
                    values = dict(zip(wanted, row))
                    explicit_name = sanitize(values.get("name"))
                    fallback_title = None
                    for column in ("title", "first_user_message"):
                        fallback_title = sanitize(values.get(column))
                        if fallback_title:
                            break
                    return explicit_name, fallback_title
            finally:
                connection.close()
        except (OSError, sqlite3.Error):
            continue
    return None, None


def title_from_notification(notification):
    messages = notification.get("input-messages")
    if not isinstance(messages, list):
        return None
    for message in messages:
        title = sanitize(message)
        if title:
            return title
    return None


def rename_agent(pane_id, socket_path, title):
    request = {
        "id": "{}:{}:{:06d}".format(
            SOURCE, int(time.time() * 1000), random.randrange(1_000_000)
        ),
        "method": "agent.rename",
        "params": {
            "target": pane_id,
            "name": title,
        },
    }
    payload = (json.dumps(request, separators=(",", ":")) + "\n").encode()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    try:
        client.connect(socket_path)
        client.sendall(payload)
    finally:
        client.close()


def previous_notify(home):
    state_path = os.path.join(home, STATE_FILE)
    try:
        with open(state_path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return None
    command = state.get("previous_notify") if isinstance(state, dict) else None
    if not isinstance(command, list) or not command:
        return None
    if not all(isinstance(part, str) and part for part in command):
        return None
    return command


def chain_previous_notify(home, raw_notification):
    command = previous_notify(home)
    if not command:
        return
    try:
        subprocess.Popen(
            command + [raw_notification],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def handle(raw_notification):
    home = codex_home()
    try:
        notification = json.loads(raw_notification)
        if not isinstance(notification, dict):
            return
        if notification.get("type") != "agent-turn-complete":
            return
        if os.environ.get("HERDR_ENV") != "1":
            return
        pane_id = os.environ.get("HERDR_PANE_ID")
        socket_path = os.environ.get("HERDR_SOCKET_PATH")
        thread_id = notification.get("thread-id")
        if not all(isinstance(value, str) and value for value in (
            pane_id, socket_path, thread_id
        )):
            return
        database_name, database_fallback = titles_from_database(home, thread_id)
        # Current Codex versions persist /rename in SQLite `name`. Older
        # sessions keep it in session_index.jsonl while SQLite `title` remains
        # the first prompt. Prefer either explicit-name store over that title.
        title = database_name
        if not title:
            title = title_from_session_index(home, thread_id)
        if not title:
            title = database_fallback
        if not title:
            title = title_from_notification(notification)
        if title:
            rename_agent(pane_id, socket_path, title)
    finally:
        chain_previous_notify(home, raw_notification)


def main(argv):
    if len(argv) != 2:
        return 0
    try:
        handle(argv[1])
    except Exception:
        # A notification callback must never disturb Codex.
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
