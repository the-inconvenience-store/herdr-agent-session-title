#!/usr/bin/env python3
"""Register, remove, or inspect a plugin entry in opencode's cli.json."""

import json
import os
import sys
import tempfile

BACKUP_FILE = "cli.json.bak-herdr-agent-session-title"


def load(path):
    """Return (config, raw text); (None, "") when the file does not exist."""
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except FileNotFoundError:
        return None, ""
    if not text.strip():
        return {}, text
    try:
        config = json.loads(text)
    except ValueError:
        raise SystemExit(
            "error: {} is not valid JSON (comments are not supported); "
            "refusing to modify".format(path)
        )
    if not isinstance(config, dict):
        raise SystemExit(
            "error: {} does not contain a JSON object; refusing to modify".format(path)
        )
    plugins = config.get("plugins")
    if plugins is not None and not isinstance(plugins, list):
        raise SystemExit(
            'error: "plugins" in {} is not an array; refusing to modify'.format(path)
        )
    return config, text


def atomic_write(path, text):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    try:
        mode = os.stat(path).st_mode & 0o777
    except FileNotFoundError:
        mode = None
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".cli-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        if mode is not None:
            os.chmod(temporary, mode)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def dump(config):
    return json.dumps(config, indent=2, ensure_ascii=False) + "\n"


def install(path, entry):
    config, text = load(path)
    plugins = list((config or {}).get("plugins") or [])
    if entry in plugins:
        print("opencode integration already registered")
        return
    if text.strip():
        atomic_write(os.path.join(os.path.dirname(path), BACKUP_FILE), text)
    updated = dict(config or {})
    updated["plugins"] = plugins + [entry]
    atomic_write(path, dump(updated))
    print("registered opencode TUI plugin in {}".format(path))


def uninstall(path, entry):
    config, _ = load(path)
    plugins = list((config or {}).get("plugins") or [])
    if entry not in plugins:
        print("opencode integration is not registered")
        return
    remaining = [item for item in plugins if item != entry]
    updated = dict(config)
    if remaining:
        updated["plugins"] = remaining
    else:
        del updated["plugins"]
    atomic_write(path, dump(updated))
    print("unregistered opencode TUI plugin from {}".format(path))


def status(path, entry):
    try:
        config, _ = load(path)
    except SystemExit:
        print("cli.json: unreadable or malformed")
        return 1
    registered = entry in ((config or {}).get("plugins") or [])
    print("cli.json entry: {}".format("registered" if registered else "NOT registered"))
    return 0 if registered else 1


def main(argv):
    if len(argv) == 3 and argv[1] == "check":
        load(argv[2])
        return 0
    if len(argv) != 4 or argv[1] not in ("install", "uninstall", "status"):
        print(
            "usage: opencode-cli-config.py check <cli.json>\n"
            "       opencode-cli-config.py install|uninstall|status <cli.json> <entry>",
            file=sys.stderr,
        )
        return 2
    action, path, entry = argv[1:]
    if action == "install":
        install(path, entry)
        return 0
    if action == "uninstall":
        uninstall(path, entry)
        return 0
    return status(path, entry)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
