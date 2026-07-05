#!/usr/bin/env python3
"""Reports the Claude Code session title to herdr as pane metadata title.

Modes:
  (no args)                             hook mode: Claude Code hook input JSON on stdin
  extract <transcript_path> <sid>       print extracted title (test entrypoint)
"""
import json
import os
import sys

SOURCE = "plugin:claude-session-title"
MAX_TITLE_CHARS = 120


def sanitize(title):
    if not isinstance(title, str):
        return None
    cleaned = "".join(ch if ch >= " " else " " for ch in title)
    cleaned = " ".join(cleaned.split())
    if not cleaned:
        return None
    return cleaned[:MAX_TITLE_CHARS]


def custom_title_from_transcript(transcript_path):
    title = None
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if '"custom-title"' not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(record, dict) or record.get("type") != "custom-title":
                    continue
                candidate = sanitize(record.get("customTitle"))
                if candidate:
                    title = candidate
    except OSError:
        return None
    return title


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
    title = custom_title_from_transcript(transcript_path)
    if title:
        return title
    return summary_from_index(transcript_path, session_id)


def main():
    args = sys.argv[1:]
    if args[:1] == ["extract"] and len(args) == 3:
        title = extract_title(args[1], args[2])
        if not title:
            return 1
        print(title)
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
