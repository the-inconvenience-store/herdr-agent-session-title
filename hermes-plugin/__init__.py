"""Mirror Hermes session titles into the matching Herdr agent name."""

# HERDR_INTEGRATION_ID=hermes-session-title
# HERDR_INTEGRATION_VERSION=1

from __future__ import annotations

import json
import os
import random
import re
import socket
import threading
import time

_SOURCE = "plugin:herdr-agent-session-title"
_INTERACTIVE_PLATFORMS = frozenset({"cli", "tui", "desktop", "acp"})
_AUTO_WATCH_SECONDS = 30.0
_COMMAND_WATCH_SECONDS = 3.0
_POLL_SECONDS = 0.25
_MAX_TITLE_CHARS = 120

_state_lock = threading.Lock()
_last_sent: dict[str, str] = {}
_auto_watch_sessions: set[str] = set()


def _sanitize(title: object) -> str | None:
    if not isinstance(title, str):
        return None
    cleaned = "".join(
        ch if ch >= " " and ch not in ("\x7f", "\x9b") else " "
        for ch in title
    )
    cleaned = " ".join(cleaned.split())
    return cleaned[:_MAX_TITLE_CHARS] or None


def _normalize_agent_name(title: object) -> str | None:
    cleaned = _sanitize(title)
    if not cleaned:
        return None
    normalized = re.sub(r"[^a-z0-9_-]+", "-", cleaned.lower())
    normalized = re.sub(r"[-_]+", "-", normalized).strip("-_")
    normalized = normalized[:32].rstrip("-_")
    if not normalized or not normalized[0].isalpha():
        normalized = ("session-" + normalized)[:32].rstrip("-_")
    return normalized or None


def _pane_context() -> tuple[str, str] | None:
    if os.environ.get("HERDR_ENV") != "1":
        return None
    pane_id = os.environ.get("HERDR_PANE_ID", "").strip()
    socket_path = os.environ.get("HERDR_SOCKET_PATH", "").strip()
    if not pane_id or not socket_path:
        return None
    return pane_id, socket_path


def _rename_agent(name: str) -> bool:
    context = _pane_context()
    if context is None:
        return False
    pane_id, socket_path = context
    request = {
        "id": "{}:{}:{:06d}".format(
            _SOURCE, int(time.time() * 1000), random.randrange(1_000_000)
        ),
        "method": "agent.rename",
        "params": {"target": pane_id, "name": name},
    }
    payload = (json.dumps(request, separators=(",", ":")) + "\n").encode()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    try:
        client.connect(socket_path)
        client.sendall(payload)
        response = b""
        while not response.endswith(b"\n"):
            chunk = client.recv(4096)
            if not chunk:
                break
            response += chunk
        parsed = json.loads(response.decode())
        return isinstance(parsed, dict) and not parsed.get("error")
    finally:
        client.close()


def _send_title(session_id: str, title: object) -> None:
    name = _normalize_agent_name(title)
    if not name:
        return
    with _state_lock:
        if _last_sent.get(session_id) == name:
            return
    if _rename_agent(name):
        with _state_lock:
            _last_sent[session_id] = name


def _open_session_db():
    from hermes_state import SessionDB

    return SessionDB(read_only=True)


def _get_title(session_id: str) -> str | None:
    db = _open_session_db()
    try:
        return _sanitize(db.get_session_title(session_id))
    finally:
        db.close()


def _watch_title(
    session_id: str,
    baseline: str | None,
    timeout: float,
    wait_for_final_source: bool,
) -> None:
    db = None
    observed = baseline
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            if db is None:
                try:
                    db = _open_session_db()
                except Exception:
                    time.sleep(_POLL_SECONDS)
                    continue
            try:
                title = _sanitize(db.get_session_title(session_id))
                source_getter = getattr(db, "get_session_title_source", None)
                source = source_getter(session_id) if callable(source_getter) else None
            except Exception:
                try:
                    db.close()
                except Exception:
                    pass
                db = None
                time.sleep(_POLL_SECONDS)
                continue
            if title and title != observed:
                _send_title(session_id, title)
                observed = title
                if not wait_for_final_source:
                    return
            if title and wait_for_final_source and source in {"llm", "user"}:
                return
            time.sleep(_POLL_SECONDS)
    finally:
        if db is not None:
            try:
                db.close()
            except Exception:
                pass
        if wait_for_final_source:
            with _state_lock:
                _auto_watch_sessions.discard(session_id)


def _start_watch(
    session_id: str,
    baseline: str | None,
    timeout: float,
    *,
    wait_for_final_source: bool,
) -> None:
    if wait_for_final_source:
        with _state_lock:
            if session_id in _auto_watch_sessions:
                return
            _auto_watch_sessions.add(session_id)
    thread = threading.Thread(
        target=_watch_title,
        args=(session_id, baseline, timeout, wait_for_final_source),
        daemon=True,
        name="herdr-hermes-title",
    )
    try:
        thread.start()
    except Exception:
        if wait_for_final_source:
            with _state_lock:
                _auto_watch_sessions.discard(session_id)


def _interactive_session(kwargs: dict) -> str | None:
    if _pane_context() is None:
        return None
    if kwargs.get("platform") not in _INTERACTIVE_PLATFORMS:
        return None
    session_id = kwargs.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        return None
    return session_id


def _sync_session(**kwargs) -> None:
    try:
        session_id = _interactive_session(kwargs)
        if session_id is None:
            return
        title = _get_title(session_id)
        if title:
            _send_title(session_id, title)
    except Exception:
        pass


def _before_turn(**kwargs) -> None:
    try:
        if kwargs.get("parent_session_id"):
            return
        session_id = _interactive_session(kwargs)
        if session_id is None:
            return
        try:
            title = _get_title(session_id)
        except Exception:
            title = None
        if title:
            _send_title(session_id, title)
            return
        _start_watch(
            session_id,
            None,
            _AUTO_WATCH_SECONDS,
            wait_for_final_source=True,
        )
    except Exception:
        pass


def _before_command(**kwargs) -> None:
    try:
        if _pane_context() is None:
            return
        if kwargs.get("platform") not in _INTERACTIVE_PLATFORMS:
            return
        command = str(kwargs.get("command") or "").lower()
        if command != "title":
            return
        if not str(kwargs.get("args_raw") or "").strip():
            return
        session_id = kwargs.get("session_key")
        if not isinstance(session_id, str) or not session_id:
            return
        try:
            baseline = _get_title(session_id)
        except Exception:
            baseline = None
        _start_watch(
            session_id,
            baseline,
            _COMMAND_WATCH_SECONDS,
            wait_for_final_source=False,
        )
    except Exception:
        pass


def register(ctx) -> None:
    ctx.register_hook("on_session_start", _sync_session)
    ctx.register_hook("pre_llm_call", _before_turn)
    ctx.register_hook("on_session_end", _sync_session)
    ctx.register_hook("pre_command", _before_command)
