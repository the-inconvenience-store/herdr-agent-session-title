#!/usr/bin/env python3
"""Install, remove, or inspect the Claude Code status-line integration."""

import copy
import json
import os
import shlex
import sys
import tempfile

BACKUP_FILE = "settings.json.bak-herdr-agent-session-title"
LEGACY_MARKER = "herdr-claude-session-title.sh"


def read_settings(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            settings = json.load(handle)
    except (OSError, ValueError) as error:
        raise SystemExit(
            "error: settings.json is unreadable or malformed; "
            "refusing to modify: {}".format(error)
        )
    if not isinstance(settings, dict):
        raise SystemExit(
            "error: settings.json root is not a JSON object; refusing to modify"
        )
    return settings


def atomic_json_write(path, value):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".settings-")
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


def load_state(path):
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        raise SystemExit(
            "error: integration state is unreadable or malformed: {}".format(error)
        )
    if not isinstance(state, dict):
        raise SystemExit("error: integration state is not a JSON object")
    return state


def validate_status_line(value):
    if value is None:
        return None
    if not isinstance(value, dict):
        raise SystemExit(
            "error: existing Claude statusLine setting is not an object"
        )
    command = value.get("command")
    if (
        value.get("type") != "command"
        or not isinstance(command, str)
        or not command.strip()
    ):
        raise SystemExit(
            "error: existing Claude statusLine is not a supported command status line"
        )
    return value


def callback_command(callback_path):
    return "python3 {}".format(shlex.quote(callback_path))


def is_ours(status_line, callback_path):
    return (
        isinstance(status_line, dict)
        and status_line.get("command") == callback_command(callback_path)
    )


def remove_legacy_hooks(settings):
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return 0
    removed = 0
    for event in list(hooks):
        entries = hooks.get(event)
        if not isinstance(entries, list):
            continue
        kept_entries = []
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
                kept_entries.append(entry)
                continue
            kept_hooks = []
            for hook in entry["hooks"]:
                if (
                    isinstance(hook, dict)
                    and LEGACY_MARKER in str(hook.get("command", ""))
                ):
                    removed += 1
                else:
                    kept_hooks.append(hook)
            if kept_hooks:
                updated = dict(entry)
                updated["hooks"] = kept_hooks
                kept_entries.append(updated)
        if kept_entries:
            hooks[event] = kept_entries
        else:
            del hooks[event]
    if not hooks:
        settings.pop("hooks", None)
    return removed


def write_backup(settings_path, settings):
    backup_path = os.path.join(os.path.dirname(settings_path), BACKUP_FILE)
    atomic_json_write(backup_path, settings)


def install(settings_path, state_path, callback_path):
    settings = read_settings(settings_path)
    original_settings = copy.deepcopy(settings)
    current = validate_status_line(settings.get("statusLine"))
    state = load_state(state_path)

    if state is not None:
        legacy_callback = os.path.join(
            os.path.dirname(callback_path), "herdr-claude-session-title.py"
        )
        migrating = is_ours(current, legacy_callback)
        if not is_ours(current, callback_path) and not migrating:
            raise SystemExit(
                "error: integration state exists but Claude statusLine was changed; "
                "run the Claude uninstall action before reinstalling"
            )
        if migrating:
            migrated = copy.deepcopy(current)
            migrated["command"] = callback_command(callback_path)
            settings["statusLine"] = migrated
            state["callback"] = callback_path
        removed = remove_legacy_hooks(settings)
        if settings != original_settings:
            write_backup(settings_path, original_settings)
            atomic_json_write(settings_path, settings)
        if migrating:
            atomic_json_write(state_path, state)
        print("Claude status-line integration already installed")
        if migrating:
            print("migrated legacy callback filename")
        if removed:
            print("removed {} legacy hook registration(s)".format(removed))
        return

    active = copy.deepcopy(current) if current is not None else {}
    active["type"] = "command"
    active["command"] = callback_command(callback_path)
    settings["statusLine"] = active
    removed = remove_legacy_hooks(settings)

    write_backup(settings_path, original_settings)
    atomic_json_write(
        state_path,
        {"previous_status_line": current, "callback": callback_path},
    )
    atomic_json_write(settings_path, settings)
    print("registered Claude status-line integration")
    if removed:
        print("removed {} legacy hook registration(s)".format(removed))


def uninstall(settings_path, state_path, callback_path):
    settings = read_settings(settings_path)
    original_settings = copy.deepcopy(settings)
    current = settings.get("statusLine")
    state = load_state(state_path)

    if state is not None and not is_ours(current, callback_path):
        print(
            "Claude statusLine was changed; leaving integration state and callback untouched",
            file=sys.stderr,
        )
        return False

    if is_ours(current, callback_path):
        previous = state.get("previous_status_line") if state is not None else None
        if previous is None:
            settings.pop("statusLine", None)
        else:
            settings["statusLine"] = validate_status_line(previous)

    removed = remove_legacy_hooks(settings)
    if settings != original_settings:
        write_backup(settings_path, original_settings)
        atomic_json_write(settings_path, settings)
    if state is not None:
        os.unlink(state_path)
    print("Claude status-line integration removed")
    if removed:
        print("removed {} legacy hook registration(s)".format(removed))
    return True


def status(settings_path, state_path, callback_path):
    try:
        settings = read_settings(settings_path)
        state = load_state(state_path)
    except SystemExit:
        print("settings.json or integration state: unreadable or malformed")
        return 1
    current = settings.get("statusLine")
    legacy = 0
    hooks = settings.get("hooks")
    if isinstance(hooks, dict):
        for entries in hooks.values():
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                for hook in entry.get("hooks", []):
                    if (
                        isinstance(hook, dict)
                        and LEGACY_MARKER in str(hook.get("command", ""))
                    ):
                        legacy += 1
    callback_installed = os.path.isfile(callback_path)
    registered = is_ours(current, callback_path)
    print("callback script: {}".format(
        "installed" if callback_installed else "NOT installed"
    ))
    print("Claude statusLine: {}".format(
        "registered" if registered else "NOT registered"
    ))
    print("previous status line preservation: {}".format(
        "recorded" if isinstance(state, dict) else "not recorded"
    ))
    print("legacy hook registrations: {}".format(legacy))
    return 0 if callback_installed and registered and legacy == 0 else 1


def main(argv):
    if len(argv) != 5 or argv[1] not in ("install", "uninstall", "status"):
        print(
            "usage: claude-statusline-config.py install|uninstall|status "
            "<settings> <state> <callback>",
            file=sys.stderr,
        )
        return 2
    action, settings_path, state_path, callback_path = argv[1:]
    if action == "install":
        install(settings_path, state_path, callback_path)
        return 0
    if action == "uninstall":
        return 0 if uninstall(settings_path, state_path, callback_path) else 1
    return status(settings_path, state_path, callback_path)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
