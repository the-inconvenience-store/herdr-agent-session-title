#!/usr/bin/env python3
"""Behavior tests for the Hermes session-title plugin."""

import importlib.util
import json
import os
import socket
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN_PATH = ROOT / "hermes-plugin" / "__init__.py"
spec = importlib.util.spec_from_file_location("herdr_hermes_title", PLUGIN_PATH)
plugin = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(plugin)


class FakeDB:
    titles = {}
    sources = {}

    def __init__(self):
        self.closed = False

    def get_session_title(self, session_id):
        return self.titles.get(session_id)

    def get_session_title_source(self, session_id):
        return self.sources.get(session_id)

    def close(self):
        self.closed = True


class FakeContext:
    def __init__(self):
        self.hooks = {}

    def register_hook(self, name, callback):
        self.hooks[name] = callback


def wait_for(predicate, message):
    deadline = time.monotonic() + 1.0
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.005)
    raise AssertionError(message)


os.environ.update(
    HERDR_ENV="1",
    HERDR_PANE_ID="w1:p1",
    HERDR_SOCKET_PATH="/tmp/herdr-test.sock",
)
plugin._POLL_SECONDS = 0.005
plugin._AUTO_WATCH_SECONDS = 0.5
plugin._COMMAND_WATCH_SECONDS = 0.5
plugin._open_session_db = FakeDB
renames = []
plugin._rename_agent = lambda name: renames.append(name) or True

ctx = FakeContext()
plugin.register(ctx)
assert set(ctx.hooks) == {
    "on_session_start",
    "pre_llm_call",
    "on_session_end",
    "pre_command",
}

FakeDB.titles["resumed"] = "Plan Move to Melbourne"
FakeDB.sources["resumed"] = "llm"
ctx.hooks["on_session_start"](session_id="resumed", platform="cli")
assert renames == ["plan-move-to-melbourne"], renames
ctx.hooks["on_session_end"](session_id="resumed", platform="cli")
assert renames == ["plan-move-to-melbourne"], renames

FakeDB.titles["child"] = "Child Session"
ctx.hooks["pre_llm_call"](
    session_id="child", platform="cli", parent_session_id="parent"
)
assert renames == ["plan-move-to-melbourne"], renames
ctx.hooks["pre_llm_call"](
    session_id="gateway", platform="telegram", parent_session_id=""
)
assert renames == ["plan-move-to-melbourne"], renames

FakeDB.titles.pop("fresh", None)
FakeDB.sources.pop("fresh", None)
ctx.hooks["pre_llm_call"](
    session_id="fresh", platform="cli", parent_session_id=""
)
FakeDB.titles["fresh"] = "Investigate Login Failure"
FakeDB.sources["fresh"] = "derived"
wait_for(
    lambda: "investigate-login-failure" in renames,
    "derived title was not reported",
)
FakeDB.titles["fresh"] = "Fix Login Redirect Loop"
FakeDB.sources["fresh"] = "llm"
wait_for(
    lambda: "fix-login-redirect-loop" in renames,
    "LLM title upgrade was not reported",
)
wait_for(
    lambda: "fresh" not in plugin._auto_watch_sessions,
    "auto-title watcher did not stop after final title",
)

FakeDB.titles["manual"] = "Old Name"
FakeDB.sources["manual"] = "llm"
ctx.hooks["on_session_start"](session_id="manual", platform="cli")
ctx.hooks["pre_command"](
    surface="cli",
    command="title",
    alias_used="title",
    args_raw="Manual Name",
    session_key="manual",
    platform="cli",
)
FakeDB.titles["manual"] = "Manual Name"
FakeDB.sources["manual"] = "user"
wait_for(lambda: "manual-name" in renames, "manual title was not reported")
manual_count = renames.count("manual-name")
ctx.hooks["pre_command"](
    surface="cli",
    command="title",
    alias_used="title",
    args_raw="",
    session_key="manual",
    platform="cli",
)
time.sleep(0.02)
assert renames.count("manual-name") == manual_count, renames

assert plugin._normalize_agent_name("  123 Strange__TITLE!!  ") == "session-123-strange-title"
assert plugin._normalize_agent_name("x" * 80) == "x" * 32

old_open = plugin._open_session_db
plugin._open_session_db = lambda: (_ for _ in ()).throw(RuntimeError("db unavailable"))
ctx.hooks["on_session_start"](session_id="broken", platform="cli")
ctx.hooks["pre_llm_call"](
    session_id="broken", platform="cli", parent_session_id=""
)
ctx.hooks["pre_command"](
    surface="cli",
    command="title",
    alias_used="title",
    args_raw="Name",
    session_key="broken",
    platform="cli",
)
plugin._open_session_db = old_open

with tempfile.TemporaryDirectory() as tmp:
    socket_path = str(Path(tmp) / "herdr.sock")
    received = []
    ready = threading.Event()

    def serve():
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            server.bind(socket_path)
            server.listen(1)
            ready.set()
            connection, _ = server.accept()
            with connection:
                payload = b""
                while not payload.endswith(b"\n"):
                    payload += connection.recv(4096)
                received.append(json.loads(payload))
                response = {"id": received[0]["id"], "result": {"ok": True}}
                connection.sendall((json.dumps(response) + "\n").encode())
        finally:
            server.close()

    server_thread = threading.Thread(target=serve, daemon=True)
    server_thread.start()
    ready.wait(1.0)
    os.environ["HERDR_SOCKET_PATH"] = socket_path
    original_rename = plugin._rename_agent
    # Recover the real transport function by loading a second module instance.
    transport_spec = importlib.util.spec_from_file_location(
        "herdr_hermes_title_transport", PLUGIN_PATH
    )
    transport = importlib.util.module_from_spec(transport_spec)
    assert transport_spec.loader is not None
    transport_spec.loader.exec_module(transport)
    assert transport._rename_agent("socket-title") is True
    server_thread.join(1.0)
    assert received[0]["method"] == "agent.rename", received
    assert received[0]["params"] == {
        "target": "w1:p1",
        "name": "socket-title",
    }, received

print("test-hermes-plugin: OK")
