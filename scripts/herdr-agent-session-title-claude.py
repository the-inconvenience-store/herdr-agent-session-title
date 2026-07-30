#!/usr/bin/env python3
"""Reports the Claude Code session title to herdr as pane metadata title.

Modes:
  (no args)                             Claude status-line JSON on stdin
  extract <transcript_path> <sid>       print extracted title (test entrypoint)
"""
import json
import os
import random
import socket
import subprocess
import sys
import time

SOURCE = "plugin:herdr-agent-session-title"
MAX_TITLE_CHARS = 120
STATE_FILE = "herdr-session-title-statusline-state.json"


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


def title_from_transcript(transcript_path):
    # /rename writes {"type":"custom-title","customTitle":...}; Claude Code's
    # auto-naming writes {"type":"ai-title","aiTitle":...}. A user-chosen name
    # always beats the auto name, regardless of which record appears later.
    custom_title = None
    ai_title = None
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if '"custom-title"' not in line and '"ai-title"' not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict):
                    continue
                if record.get("type") == "custom-title":
                    candidate = sanitize(record.get("customTitle"))
                    if candidate:
                        custom_title = candidate
                elif record.get("type") == "ai-title":
                    candidate = sanitize(record.get("aiTitle"))
                    if candidate:
                        ai_title = candidate
    except OSError:
        return None
    return custom_title or ai_title


def summary_from_index(transcript_path, session_id):
    index_path = os.path.join(os.path.dirname(transcript_path), "sessions-index.json")
    try:
        with open(index_path, encoding="utf-8") as handle:
            index = json.load(handle)
    except (OSError, ValueError):
        return None
    entries = index.get("entries") if isinstance(index, dict) else None
    if not isinstance(entries, list):
        return None
    for entry in entries:
        if isinstance(entry, dict) and entry.get("sessionId") == session_id:
            return sanitize(entry.get("summary"))
    return None


def extract_title(transcript_path, session_id):
    title = title_from_transcript(transcript_path)
    if title:
        return title
    # last resort: legacy index (current Claude Code no longer maintains it,
    # but old sessions may still have a summary there)
    return summary_from_index(transcript_path, session_id)


def report(pane_id, socket_path, title):
    request = {
        "id": "{}:{}:{:06d}".format(SOURCE, int(time.time() * 1000), random.randrange(1_000_000)),
        "method": "pane.report_metadata",
        "params": {
            "pane_id": pane_id,
            "source": SOURCE,
            "agent": "claude",
            "title": title,
            "seq": time.time_ns(),
        },
    }
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    try:
        client.connect(socket_path)
        client.sendall((json.dumps(request) + "\n").encode())
        try:
            client.recv(4096)
        except OSError:
            pass
    finally:
        client.close()


def claude_home():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")


def previous_status_line():
    state_path = os.path.join(claude_home(), STATE_FILE)
    try:
        with open(state_path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return None
    previous = state.get("previous_status_line") if isinstance(state, dict) else None
    if not isinstance(previous, dict):
        return None
    command = previous.get("command")
    if not isinstance(command, str) or not command.strip():
        return None
    return command


def chain_previous_status_line(raw_input):
    command = previous_status_line()
    if not command:
        return
    try:
        completed = subprocess.run(
            command,
            input=raw_input,
            text=True,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        sys.stdout.write(completed.stdout)
        sys.stderr.write(completed.stderr)
    except OSError:
        pass


def status_line_mode():
    raw_input = sys.stdin.read()
    try:
        status_input = json.loads(raw_input)
        if not isinstance(status_input, dict):
            return
        pane_id = os.environ.get("HERDR_PANE_ID")
        socket_path = os.environ.get("HERDR_SOCKET_PATH")
        session_id = status_input.get("session_id")
        transcript_path = status_input.get("transcript_path")
        if not all(
            isinstance(value, str) and value
            for value in (pane_id, socket_path, session_id)
        ):
            return
        title = sanitize(status_input.get("session_name"))
        if not title and isinstance(transcript_path, str):
            title = extract_title(transcript_path, session_id)
        if title:
            report(pane_id, socket_path, title)
    finally:
        chain_previous_status_line(raw_input)


def main():
    args = sys.argv[1:]
    if args[:1] == ["extract"] and len(args) == 3:
        title = extract_title(args[1], args[2])
        if not title:
            return 1
        print(title)
        return 0
    try:
        status_line_mode()
    except Exception:
        # A status-line command must never disturb Claude Code.
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
