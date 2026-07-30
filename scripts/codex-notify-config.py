#!/usr/bin/env python3
"""Install, remove, or inspect the Codex notify integration."""

import json
import os
import re
import sys
import tempfile
import ast

STATE_FILE = "herdr-session-title-notify-state.json"
BACKUP_FILE = "config.toml.bak-codex-session-title"
KEY_RE = re.compile(r"^[ \t]*notify[ \t]*=")
TABLE_RE = re.compile(r"^[ \t]*\[")


def read_text(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except FileNotFoundError:
        return ""


def root_notify_span(text):
    lines = text.splitlines(keepends=True)
    offset = 0
    start = None
    for line in lines:
        if TABLE_RE.match(line):
            break
        if KEY_RE.match(line):
            start = offset
            break
        offset += len(line)
    if start is None:
        return None

    equals = text.find("=", start)
    index = equals + 1
    bracket_depth = 0
    in_string = False
    string_quote = None
    escaped = False
    saw_value = False
    while index < len(text):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\" and string_quote == '"':
                escaped = True
            elif char == string_quote:
                in_string = False
        elif char in ('"', "'"):
            in_string = True
            string_quote = char
            saw_value = True
        elif char == "[":
            bracket_depth += 1
            saw_value = True
        elif char == "]":
            bracket_depth -= 1
        elif char == "#":
            newline = text.find("\n", index)
            index = len(text) if newline == -1 else newline
            continue
        elif char == "\n" and saw_value and bracket_depth == 0:
            return start, index + 1
        elif not char.isspace():
            saw_value = True
        index += 1
    return start, len(text)


def notify_from_text(text):
    span = root_notify_span(text)
    if span is None:
        return None
    assignment = text[slice(*span)]
    value_text = assignment.split("=", 1)[1].strip()
    try:
        value = ast.literal_eval(value_text)
    except (SyntaxError, ValueError):
        raise SystemExit(
            "error: existing Codex notify setting could not be parsed; "
            "refusing to modify"
        )
    return validate_notify(value)


def atomic_write(path, text):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".config-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def notify_line(command):
    return "notify = {}\n".format(json.dumps(command, ensure_ascii=True))


def validate_notify(value):
    if value is None:
        return None
    if not isinstance(value, list) or not value:
        raise SystemExit("error: existing Codex notify setting is not a non-empty array")
    if not all(isinstance(part, str) and part for part in value):
        raise SystemExit("error: existing Codex notify command contains a non-string value")
    return value


def load_state(path):
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        return None
    except ValueError:
        raise SystemExit("error: integration state is malformed: {}".format(path))
    return state


def install(config_path, state_path, callback_path):
    text = read_text(config_path)
    current = notify_from_text(text)
    ours = ["python3", callback_path]
    existing_state = load_state(state_path)
    if existing_state is not None:
        if current == ours:
            print("Codex notify integration already installed")
            return
        raise SystemExit(
            "error: integration state exists but Codex notify was changed; "
            "run the Codex uninstall action before reinstalling"
        )

    span = root_notify_span(text)
    previous_assignment = text[slice(*span)] if span else None
    if current is not None and span is None:
        raise SystemExit("error: could not locate the top-level Codex notify assignment")

    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    if text:
        atomic_write(os.path.join(os.path.dirname(config_path), BACKUP_FILE), text)
    state = {
        "previous_notify": current,
        "previous_assignment": previous_assignment,
        "callback": callback_path,
    }
    atomic_write(state_path, json.dumps(state, indent=2) + "\n")

    replacement = notify_line(ours)
    if span:
        updated = text[:span[0]] + replacement + text[span[1]:]
    else:
        updated = replacement + text
    atomic_write(config_path, updated)
    print("registered Codex agent-turn-complete notification")


def uninstall(config_path, state_path, callback_path):
    state = load_state(state_path)
    if state is None:
        print("Codex notify integration is not installed")
        return True

    text = read_text(config_path)
    current = notify_from_text(text)
    ours = ["python3", callback_path]
    if current != ours:
        print("Codex notify setting was changed; leaving config.toml untouched", file=sys.stderr)
        return False

    span = root_notify_span(text)
    if span is None:
        print("Codex notify assignment is missing; leaving config.toml untouched", file=sys.stderr)
        return False
    previous = state.get("previous_assignment")
    replacement = previous if isinstance(previous, str) else ""
    updated = text[:span[0]] + replacement + text[span[1]:]
    atomic_write(config_path, updated)
    os.unlink(state_path)
    print("Codex notify integration removed")
    return True


def status(config_path, state_path, callback_path):
    state = load_state(state_path)
    try:
        current = notify_from_text(read_text(config_path))
    except SystemExit:
        print("config.toml: unreadable or malformed")
        return 1
    ours = ["python3", callback_path]
    print("callback script: {}".format(
        "installed" if os.path.isfile(callback_path) else "NOT installed"
    ))
    print("Codex notify: {}".format("registered" if current == ours else "NOT registered"))
    print("previous notify preservation: {}".format(
        "recorded" if isinstance(state, dict) else "not recorded"
    ))
    return 0 if current == ours and os.path.isfile(callback_path) else 1


def main(argv):
    if len(argv) != 5 or argv[1] not in ("install", "uninstall", "status"):
        print(
            "usage: codex-notify-config.py install|uninstall|status "
            "<config> <state> <callback>",
            file=sys.stderr,
        )
        return 2
    action, config_path, state_path, callback_path = argv[1:]
    if action == "install":
        install(config_path, state_path, callback_path)
        return 0
    if action == "uninstall":
        return 0 if uninstall(config_path, state_path, callback_path) else 1
    return status(config_path, state_path, callback_path)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
