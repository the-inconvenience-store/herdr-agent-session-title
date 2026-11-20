#!/usr/bin/env python3
"""Install, remove, or inspect the Cursor Agent hooks integration."""

import copy
import json
import os
import shlex
import sys
import tempfile

HOOK_EVENTS = ("sessionStart", "stop")
BACKUP_FILE = "hooks.json.bak-herdr-agent-session-title"


def read_config(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, ValueError) as error:
        raise SystemExit(
            "error: hooks.json is unreadable or malformed; "
            "refusing to modify: {}".format(error)
        )
    if not isinstance(config, dict):
        raise SystemExit(
            "error: hooks.json root is not a JSON object; refusing to modify"
        )
    hooks = config.get("hooks")
    if hooks is not None and not isinstance(hooks, dict):
        raise SystemExit(
            "error: hooks.json hooks value is not a JSON object; refusing to modify"
        )
    return config


def atomic_json_write(path, value):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".hooks-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def callback_command(callback_path):
    return "python3 {}".format(shlex.quote(callback_path))


def is_ours(entry, callback_path):
    return (
        isinstance(entry, dict)
        and entry.get("command") == callback_command(callback_path)
    )


def write_backup(config_path, config):
    backup_path = os.path.join(os.path.dirname(config_path), BACKUP_FILE)
    atomic_json_write(backup_path, config)


def install(config_path, callback_path):
    config = read_config(config_path)
    original = copy.deepcopy(config)
    hooks = config.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
        config["hooks"] = hooks
    config.setdefault("version", 1)
    command = callback_command(callback_path)
    for event in HOOK_EVENTS:
        entries = hooks.get(event)
        if not isinstance(entries, list):
            entries = []
        entries = [entry for entry in entries if not is_ours(entry, callback_path)]
        entries.append({"command": command})
        hooks[event] = entries
    if config == original:
        print("Cursor hooks integration already installed")
        return
    write_backup(config_path, original)
    atomic_json_write(config_path, config)
    print("registered Cursor {} hooks".format(" and ".join(HOOK_EVENTS)))


def uninstall(config_path, callback_path):
    config = read_config(config_path)
    original = copy.deepcopy(config)
    hooks = config.get("hooks")
    removed = 0
    if isinstance(hooks, dict):
        for event in list(hooks):
            entries = hooks.get(event)
            if not isinstance(entries, list):
                continue
            kept = [entry for entry in entries if not is_ours(entry, callback_path)]
            removed += len(entries) - len(kept)
            if kept:
                hooks[event] = kept
            else:
                del hooks[event]
        if not hooks:
            del config["hooks"]
    if config != original:
        write_backup(config_path, original)
        atomic_json_write(config_path, config)
    print("Cursor hooks integration removed ({} registration(s))".format(removed))


def status(config_path, callback_path):
    try:
        config = read_config(config_path)
    except SystemExit:
        print("hooks.json: unreadable or malformed")
        return 1
    hooks = config.get("hooks")
    registered = 0
    if isinstance(hooks, dict):
        for event in HOOK_EVENTS:
            entries = hooks.get(event)
            if isinstance(entries, list) and any(
                is_ours(entry, callback_path) for entry in entries
            ):
                registered += 1
    print("callback script: {}".format(
        "installed" if os.path.isfile(callback_path) else "NOT installed"
    ))
    print("Cursor hooks: {}".format(
        "registered" if registered == len(HOOK_EVENTS) else "NOT registered"
    ))
    return 0 if os.path.isfile(callback_path) and registered == len(HOOK_EVENTS) else 1


def main(argv):
    if len(argv) != 4 or argv[1] not in ("install", "uninstall", "status"):
        print(
            "usage: cursor-hooks-config.py install|uninstall|status "
            "<hooks.json> <callback>",
            file=sys.stderr,
        )
        return 2
    action, config_path, callback_path = argv[1:]
    if action == "install":
        install(config_path, callback_path)
        return 0
    if action == "uninstall":
        uninstall(config_path, callback_path)
        return 0
    return status(config_path, callback_path)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
