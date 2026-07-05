# claude-session-title Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code'daki oturum adını (`/rename` veya otomatik özet) herdr pane'inin metadata title alanına otomatik bildiren, bağımsız bir herdr plugin'i.

**Architecture:** Kurulum aksiyonu Claude Code ayarlarına (`~/.claude/settings.json`) üç hook kaydı ekler (SessionStart, UserPromptSubmit, Stop). Hook betiği pane ortamından devraldığı `HERDR_PANE_ID`/`HERDR_SOCKET_PATH` ile, transcript'ten çıkardığı adı herdr soketine tek bir `pane.report_metadata` isteğiyle bildirir. Herdr çekirdeğinde sıfır değişiklik.

**Tech Stack:** POSIX sh + python3 (standart kütüphane; ek bağımlılık yok). Testler saf sh betikleri.

**Spec:** `docs/superpowers/specs/2026-07-05-claude-session-title-plugin-design.md`

## Global Constraints

- Plugin id: `bcihanc.claude-session-title`; metadata source: `plugin:claude-session-title`; agent etiketi: `claude`.
- `min_herdr_version = "0.7.0"`, `platforms = ["linux", "macos"]` (Windows kapsam dışı).
- Hook betiği HİÇBİR koşulda sıfır-dışı çıkmaz ve Claude Code akışını bloklamaz: soket zaman aşımı 0,5 sn; hook kaydında `timeout: 10`.
- Title temizliği: kontrol karakterleri boşluğa çevrilir, boşluklar sadeleştirilir, 120 karakterde kesilir (`MAX_TITLE_CHARS = 120`).
- Ad öncelik sırası: transcript'teki SON `{"type":"custom-title"}` kaydı → `sessions-index.json` içindeki `entries[].summary` (sessionId eşleşmeli) → hiçbiri yoksa bildirim gönderilmez.
- `install.sh`/`uninstall.sh` yalnızca `herdr-claude-session-title.sh` marker'ını içeren hook kayıtlarına dokunur; yabancı kayıtlar aynen korunur. settings.json yazımı geçici dosya + `os.replace` (atomik) ile yapılır; düzenleme öncesi `settings.json.bak-claude-session-title` yedeği alınır.
- Kurulan dosyaların sabit yolu: `~/.claude/hooks/herdr-claude-session-title.sh` ve `~/.claude/hooks/herdr-claude-session-title.py` (`CLAUDE_CONFIG_DIR` ortam değişkeni set ise `$CLAUDE_CONFIG_DIR/hooks/...`).
- Soket isteği şekli (herdr 0.7.1 kaynağından doğrulandı): `{"id": "...", "method": "pane.report_metadata", "params": {"pane_id", "source", "agent", "title", "seq"}}` — `seq` nanosaniye zaman damgası.
- Commit stili: lowercase conventional commits, emoji yok.
- Tüm testler herdr veya Claude Code çalışmadan, çevrimdışı koşabilmeli (`sh tests/run.sh`).

---

### Task 1: Depo iskeleti ve plugin manifest'i

**Files:**
- Create: `herdr-plugin.toml`
- Create: `.gitignore`
- Create: `tests/run.sh`

**Interfaces:**
- Produces: `herdr-plugin.toml` manifest'i — sonraki task'lerin script yolları (`scripts/install.sh`, `scripts/uninstall.sh`, `scripts/status.sh`) burada bildirilir. `tests/run.sh` tüm test betiklerini sırayla koşan tek giriş noktasıdır; sonraki task'ler kendi test betiğini bu dosyaya bir satır ekleyerek kaydeder.

- [ ] **Step 1: Manifest'i yaz**

`herdr-plugin.toml`:

```toml
id = "bcihanc.claude-session-title"
name = "Claude Session Title"
version = "0.1.0"
min_herdr_version = "0.7.0"
description = "Reports the Claude Code session title (/rename or auto summary) as the herdr pane metadata title"
platforms = ["linux", "macos"]

[[actions]]
id = "install"
title = "Install Claude Code hook"
contexts = ["workspace"]
command = ["sh", "scripts/install.sh"]

[[actions]]
id = "uninstall"
title = "Uninstall Claude Code hook"
contexts = ["workspace"]
command = ["sh", "scripts/uninstall.sh"]

[[actions]]
id = "status"
title = "Show hook installation status"
contexts = ["workspace"]
command = ["sh", "scripts/status.sh"]
```

- [ ] **Step 2: .gitignore ve test koşucusunu yaz**

`.gitignore`:

```text
*.tmp
.DS_Store
```

`tests/run.sh`:

```sh
#!/bin/sh
# runs every test script; each one exits nonzero on failure
set -eu
cd "$(dirname "$0")/.."
for test_script in tests/test-*.sh; do
  echo "== $test_script"
  sh "$test_script"
done
echo "all tests: OK"
```

- [ ] **Step 3: Manifest'in geçerli TOML olduğunu doğrula**

Run: `python3 -c "import tomllib; d = tomllib.load(open('herdr-plugin.toml','rb')); assert d['id'] == 'bcihanc.claude-session-title'; assert len(d['actions']) == 3; print('manifest OK')"`
Expected: `manifest OK`
(python3 < 3.11 ise `tomllib` yoktur; bu durumda `herdr plugin link "$PWD"` çıktısında manifest hatası olmamasına bakılır — Task 6'daki link adımı bunu zaten kapsar.)

- [ ] **Step 4: Test koşucusunun boş durumda çalıştığını doğrula**

Run: `sh tests/run.sh`
Expected: glob eşleşmediği için `tests/test-*.sh` bulunamadı hatası — henüz test yok. Bu beklenen durumdur; koşucuya boş-glob koruması ekle:

`tests/run.sh` son hali:

```sh
#!/bin/sh
# runs every test script; each one exits nonzero on failure
set -eu
cd "$(dirname "$0")/.."
found=0
for test_script in tests/test-*.sh; do
  [ -e "$test_script" ] || continue
  found=1
  echo "== $test_script"
  sh "$test_script"
done
[ "$found" = "1" ] || echo "no tests yet"
echo "all tests: OK"
```

Run: `sh tests/run.sh`
Expected: `no tests yet` + `all tests: OK`

- [ ] **Step 5: Commit**

```bash
git add herdr-plugin.toml .gitignore tests/run.sh
git commit -m "feat: plugin manifest and test runner scaffold"
```

---

### Task 2: Ad çıkarma mantığı (extract) — TDD

**Files:**
- Create: `scripts/herdr-claude-session-title.py`
- Create: `tests/test-extract.sh`
- Create: `tests/fixtures/transcript-custom-title.jsonl`
- Create: `tests/fixtures/transcript-no-title.jsonl`
- Create: `tests/fixtures/transcript-garbage.jsonl`
- Create: `tests/fixtures/transcript-long-title.jsonl`
- Create: `tests/fixtures/sessions-index.json`

**Interfaces:**
- Produces: `python3 scripts/herdr-claude-session-title.py extract <transcript_path> <session_id>` — bulunan title'ı stdout'a basar, exit 0; title yoksa exit 1. Python içi API: `sanitize(title) -> str|None`, `extract_title(transcript_path, session_id) -> str|None`. Task 3 bu dosyaya hook modunu ekleyecek.

- [ ] **Step 1: Fixture'ları yaz**

`tests/fixtures/transcript-custom-title.jsonl` (iki rename — SONUNCUSU kazanmalı):

```jsonl
{"type":"custom-title","customTitle":"first-name","sessionId":"sid-1"}
{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"hello"},"sessionId":"sid-1"}
{"type":"custom-title","customTitle":"second-name","sessionId":"sid-1"}
```

`tests/fixtures/transcript-no-title.jsonl` (custom-title yok; index'e düşmeli):

```jsonl
{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"hello"},"sessionId":"sid-2"}
{"type":"assistant","message":{"role":"assistant","content":"hi"},"sessionId":"sid-2"}
```

`tests/fixtures/transcript-garbage.jsonl` (bozuk satırlar arasında geçerli kayıt):

```jsonl
this line is not json at all {{{
{"type":"custom-title","customTitle":"","sessionId":"sid-3"}
{"type":"custom-title" BROKEN JSON "customTitle":"nope"}
{"type":"custom-title","customTitle":"valid-after-garbage","sessionId":"sid-3"}
```

`tests/fixtures/transcript-long-title.jsonl` (200 karakterlik ad — 120'ye kesilmeli; `customTitle` değeri 200 adet `x` karakteri):

```jsonl
{"type":"custom-title","customTitle":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx","sessionId":"sid-5"}
```

`tests/fixtures/sessions-index.json` (sid-2 için otomatik özet; sid-4 bilerek YOK):

```json
{
  "version": 1,
  "entries": [
    {
      "sessionId": "sid-2",
      "fullPath": "/ignored/path/sid-2.jsonl",
      "firstPrompt": "hello",
      "summary": "Automatic summary title",
      "messageCount": 2,
      "created": "2026-07-05T10:00:00.000Z",
      "modified": "2026-07-05T10:05:00.000Z"
    }
  ]
}
```

- [ ] **Step 2: Başarısız olacak testi yaz**

`tests/test-extract.sh`:

```sh
#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
py="scripts/herdr-claude-session-title.py"
fx="tests/fixtures"
fail() { echo "FAIL: $1" >&2; exit 1; }

title=$(python3 "$py" extract "$fx/transcript-custom-title.jsonl" "sid-1")
[ "$title" = "second-name" ] || fail "expected last rename to win, got: $title"

title=$(python3 "$py" extract "$fx/transcript-no-title.jsonl" "sid-2")
[ "$title" = "Automatic summary title" ] || fail "expected summary fallback, got: $title"

title=$(python3 "$py" extract "$fx/transcript-garbage.jsonl" "sid-3")
[ "$title" = "valid-after-garbage" ] || fail "expected title despite garbage lines, got: $title"

title=$(python3 "$py" extract "$fx/transcript-long-title.jsonl" "sid-5")
[ "${#title}" -eq 120 ] || fail "expected 120-char truncation, got length: ${#title}"

if python3 "$py" extract "$fx/missing.jsonl" "sid-4" >/dev/null 2>&1; then
  fail "expected nonzero exit when transcript missing and session not in index"
fi

echo "test-extract: OK"
```

- [ ] **Step 3: Testi çalıştır, başarısızlığı gör**

Run: `sh tests/test-extract.sh`
Expected: FAIL — `scripts/herdr-claude-session-title.py` henüz yok (`No such file or directory`).

- [ ] **Step 4: Çıkarma mantığını yaz**

`scripts/herdr-claude-session-title.py`:

```python
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
```

- [ ] **Step 5: Testi çalıştır, geçtiğini gör**

Run: `sh tests/test-extract.sh`
Expected: `test-extract: OK`

Run: `sh tests/run.sh`
Expected: `== tests/test-extract.sh` satırı + `all tests: OK`

- [ ] **Step 6: Commit**

```bash
git add scripts/herdr-claude-session-title.py tests/test-extract.sh tests/fixtures/
git commit -m "feat: session title extraction with fixture tests"
```

---

### Task 3: Hook modu ve sh sarmalayıcı — TDD

**Files:**
- Modify: `scripts/herdr-claude-session-title.py` (hook modu eklenir)
- Create: `scripts/herdr-claude-session-title.sh`
- Create: `tests/test-socket.sh`

**Interfaces:**
- Consumes: Task 2'nin `extract_title(transcript_path, session_id)` fonksiyonu ve fixture'ları.
- Produces: `sh scripts/herdr-claude-session-title.sh` — stdin'den Claude Code hook girdisi okur; `HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_SOCKET_PATH` ortamıyla çalışır; `HERDR_SOCKET_PATH` soketine `pane.report_metadata` isteği gönderir. Task 4 bu iki dosyayı `~/.claude/hooks/` altına kopyalayacak — dosya adları sabittir.

- [ ] **Step 1: Başarısız olacak testi yaz**

`tests/test-socket.sh` (sahte herdr soket sunucusu + gerçek hook çağrısı):

```sh
#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sock="$tmp/herdr.sock"
out="$tmp/request.json"
fail() { echo "FAIL: $1" >&2; exit 1; }

# --- case 1: normal hook event reports the title ---
python3 - "$sock" "$out" <<'PY' &
import socket, sys
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
server.settimeout(10)
conn, _ = server.accept()
data = b""
while not data.endswith(b"\n"):
    chunk = conn.recv(4096)
    if not chunk:
        break
    data += chunk
with open(sys.argv[2], "wb") as handle:
    handle.write(data)
conn.sendall(b'{"id":"x","result":{"type":"ok"}}\n')
conn.close()
PY
server_pid=$!

i=0
while [ ! -S "$sock" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
[ -S "$sock" ] || fail "fake server socket did not appear"

printf '{"session_id":"sid-1","transcript_path":"%s","hook_event_name":"Stop"}' \
  "$PWD/tests/fixtures/transcript-custom-title.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$sock" \
  sh scripts/herdr-claude-session-title.sh

wait "$server_pid"

python3 - "$out" <<'PY'
import json, sys
request = json.loads(open(sys.argv[1], "rb").read().decode())
assert request["method"] == "pane.report_metadata", request
params = request["params"]
assert params["pane_id"] == "%42", params
assert params["source"] == "plugin:claude-session-title", params
assert params["agent"] == "claude", params
assert params["title"] == "second-name", params
assert isinstance(params["seq"], int) and params["seq"] > 0, params
print("case 1 (report): OK")
PY

# --- case 2: subagent event must NOT reach the socket ---
sock2="$tmp/herdr2.sock"
python3 - "$sock2" <<'PY' &
import socket, sys
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sys.argv[1])
server.listen(1)
server.settimeout(2)
try:
    server.accept()
    raise SystemExit("FAIL: subagent event reached the socket")
except socket.timeout:
    print("case 2 (subagent skip): OK")
PY
server2_pid=$!

i=0
while [ ! -S "$sock2" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done

printf '{"session_id":"sid-1","transcript_path":"%s","hook_event_name":"Stop","agent_id":"agent-xyz"}' \
  "$PWD/tests/fixtures/transcript-custom-title.jsonl" |
  HERDR_ENV=1 HERDR_PANE_ID='%42' HERDR_SOCKET_PATH="$sock2" \
  sh scripts/herdr-claude-session-title.sh

wait "$server2_pid" || fail "subagent event was reported"

# --- case 3: outside herdr the wrapper exits silently ---
printf '{"session_id":"sid-1"}' | sh scripts/herdr-claude-session-title.sh \
  || fail "wrapper must exit 0 outside herdr"

echo "test-socket: OK"
```

- [ ] **Step 2: Testi çalıştır, başarısızlığı gör**

Run: `sh tests/test-socket.sh`
Expected: FAIL — `scripts/herdr-claude-session-title.sh` henüz yok.

- [ ] **Step 3: Python'a hook modunu ekle**

`scripts/herdr-claude-session-title.py` dosyasında `import` bloğunu genişlet ve `main`'den önce şu fonksiyonları ekle (dosyanın son hali aşağıdaki parçaların Task 2'deki içerikle birleşimidir):

```python
import json
import os
import random
import socket
import sys
import time
```

```python
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


def hook_mode():
    pane_id = os.environ.get("HERDR_PANE_ID")
    socket_path = os.environ.get("HERDR_SOCKET_PATH")
    if not pane_id or not socket_path:
        return
    try:
        hook_input = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(hook_input, dict):
        return
    if hook_input.get("agent_id"):
        # subagent event: its transcript does not represent the main session
        return
    session_id = hook_input.get("session_id")
    transcript_path = hook_input.get("transcript_path")
    if not isinstance(session_id, str) or not isinstance(transcript_path, str):
        return
    title = extract_title(transcript_path, session_id)
    if not title:
        return
    report(pane_id, socket_path, title)
```

`main` fonksiyonunun son hali:

```python
def main():
    args = sys.argv[1:]
    if args[:1] == ["extract"] and len(args) == 3:
        title = extract_title(args[1], args[2])
        if not title:
            return 1
        print(title)
        return 0
    try:
        hook_mode()
    except Exception:
        # a hook must never disturb Claude Code
        pass
    return 0
```

- [ ] **Step 4: sh sarmalayıcıyı yaz**

`scripts/herdr-claude-session-title.sh`:

```sh
#!/bin/sh
# installed by the bcihanc.claude-session-title herdr plugin
# reinstalling the plugin overwrites this file; do not edit in place.
set -eu

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$script_dir/herdr-claude-session-title.py"
```

- [ ] **Step 5: Testleri çalıştır, geçtiklerini gör**

Run: `sh tests/test-socket.sh`
Expected: `case 1 (report): OK`, `case 2 (subagent skip): OK`, `test-socket: OK`

Run: `sh tests/run.sh`
Expected: iki test betiği de koşar, `all tests: OK`

- [ ] **Step 6: Commit**

```bash
git add scripts/herdr-claude-session-title.py scripts/herdr-claude-session-title.sh tests/test-socket.sh
git commit -m "feat: hook mode reporting title over herdr socket"
```

---

### Task 4: install / uninstall aksiyonları — TDD

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/uninstall.sh`
- Create: `tests/test-install.sh`

**Interfaces:**
- Consumes: Task 3'ün `scripts/herdr-claude-session-title.sh` ve `.py` dosyaları (kopyalanacak kaynaklar). Plugin aksiyonu olarak çalışırken herdr `HERDR_PLUGIN_ROOT` ortam değişkenini sağlar.
- Produces: `sh scripts/install.sh` — hook dosyalarını `$CLAUDE_CONFIG_DIR|$HOME/.claude/hooks/` altına kopyalar ve settings.json'a üç hook kaydı ekler (idempotent). `sh scripts/uninstall.sh` — yalnızca bu plugin'in kayıtlarını ve kopyalarını kaldırır. Task 5'in status.sh'i aynı yol ve marker kurallarını kullanır.

- [ ] **Step 1: Başarısız olacak testi yaz**

`tests/test-install.sh`:

```sh
#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
export HERDR_PLUGIN_ROOT="$PWD"
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "other-tool hook"}]}
    ]
  },
  "model": "opus"
}
JSON

sh scripts/install.sh >/dev/null
sh scripts/install.sh >/dev/null

python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
hooks = settings["hooks"]
marker = "herdr-claude-session-title.sh"
for event in ["SessionStart", "UserPromptSubmit", "Stop"]:
    ours = [h for e in hooks.get(event, []) for h in e.get("hooks", [])
            if marker in str(h.get("command", ""))]
    assert len(ours) == 1, ("duplicate or missing registration", event, ours)
    assert ours[0].get("timeout") == 10, ours
foreign = [h for e in hooks["Stop"] for h in e.get("hooks", [])
           if h.get("command") == "other-tool hook"]
assert len(foreign) == 1, ("foreign hook lost", foreign)
assert settings["model"] == "opus", "unrelated settings must survive"
session_start = hooks["SessionStart"]
ours_entry = [e for e in session_start
              if any(marker in str(h.get("command", "")) for h in e.get("hooks", []))]
assert ours_entry[0].get("matcher") == "*", ours_entry
print("install idempotency: OK")
PY

[ -x "$HOME/.claude/hooks/herdr-claude-session-title.sh" ] || fail "hook sh copy missing"
[ -f "$HOME/.claude/hooks/herdr-claude-session-title.py" ] || fail "hook py copy missing"
[ -f "$HOME/.claude/settings.json.bak-claude-session-title" ] || fail "backup missing"

sh scripts/uninstall.sh >/dev/null

python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
settings = json.load(open(sys.argv[1]))
raw = json.dumps(settings)
assert "herdr-claude-session-title" not in raw, raw
foreign = [h for e in settings["hooks"]["Stop"] for h in e.get("hooks", [])
           if h.get("command") == "other-tool hook"]
assert len(foreign) == 1, ("foreign hook lost on uninstall", foreign)
print("uninstall cleanup: OK")
PY

[ ! -e "$HOME/.claude/hooks/herdr-claude-session-title.sh" ] || fail "hook sh copy not removed"
[ ! -e "$HOME/.claude/hooks/herdr-claude-session-title.py" ] || fail "hook py copy not removed"

echo "test-install: OK"
```

- [ ] **Step 2: Testi çalıştır, başarısızlığı gör**

Run: `sh tests/test-install.sh`
Expected: FAIL — `scripts/install.sh` henüz yok.

- [ ] **Step 3: install.sh'i yaz**

`scripts/install.sh`:

```sh
#!/bin/sh
# herdr plugin action: registers the Claude Code hook for session title reporting
set -eu

plugin_root="${HERDR_PLUGIN_ROOT:?HERDR_PLUGIN_ROOT is not set}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
hooks_dir="$claude_dir/hooks"
hook_sh="$hooks_dir/herdr-claude-session-title.sh"
hook_py="$hooks_dir/herdr-claude-session-title.py"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

mkdir -p "$hooks_dir"
cp "$plugin_root/scripts/herdr-claude-session-title.sh" "$hook_sh"
cp "$plugin_root/scripts/herdr-claude-session-title.py" "$hook_py"
chmod +x "$hook_sh"

HOOK_COMMAND="sh '$hook_sh'" SETTINGS_PATH="$claude_dir/settings.json" python3 - <<'PY'
import json
import os
import tempfile

settings_path = os.environ["SETTINGS_PATH"]
hook_command = os.environ["HOOK_COMMAND"]
marker = "herdr-claude-session-title.sh"
events = ["SessionStart", "UserPromptSubmit", "Stop"]

settings = {}
if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as handle:
        settings = json.load(handle)
    backup = settings_path + ".bak-claude-session-title"
    with open(backup, "w", encoding="utf-8") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")

hooks = settings.setdefault("hooks", {})
for event in events:
    entries = hooks.setdefault(event, [])
    kept = []
    for entry in entries:
        if isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
            had_marker = any(
                isinstance(h, dict) and marker in str(h.get("command", ""))
                for h in entry["hooks"]
            )
            if had_marker:
                entry["hooks"] = [
                    h for h in entry["hooks"]
                    if not (isinstance(h, dict) and marker in str(h.get("command", "")))
                ]
                if not entry["hooks"]:
                    continue
        kept.append(entry)
    new_entry = {"hooks": [{"type": "command", "command": hook_command, "timeout": 10}]}
    if event == "SessionStart":
        new_entry["matcher"] = "*"
    kept.append(new_entry)
    hooks[event] = kept

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(settings_path) or ".", prefix=".settings-")
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
os.replace(tmp_path, settings_path)
print("registered hooks: " + ", ".join(events))
PY

echo "installed: $hook_sh"
echo "note: already-running Claude Code sessions pick up new hooks on restart"
```

- [ ] **Step 4: uninstall.sh'i yaz**

`scripts/uninstall.sh`:

```sh
#!/bin/sh
# herdr plugin action: removes the Claude Code hook registrations and copies
set -eu

claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
hooks_dir="$claude_dir/hooks"
settings_path="$claude_dir/settings.json"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

if [ -f "$settings_path" ]; then
  SETTINGS_PATH="$settings_path" python3 - <<'PY'
import json
import os
import tempfile

settings_path = os.environ["SETTINGS_PATH"]
marker = "herdr-claude-session-title.sh"

with open(settings_path, encoding="utf-8") as handle:
    settings = json.load(handle)

hooks = settings.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks.keys()):
        entries = hooks.get(event)
        if not isinstance(entries, list):
            continue
        kept = []
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
                had_marker = any(
                    isinstance(h, dict) and marker in str(h.get("command", ""))
                    for h in entry["hooks"]
                )
                if had_marker:
                    entry["hooks"] = [
                        h for h in entry["hooks"]
                        if not (isinstance(h, dict) and marker in str(h.get("command", "")))
                    ]
                    if not entry["hooks"]:
                        continue
            kept.append(entry)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]

fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(settings_path) or ".", prefix=".settings-")
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
os.replace(tmp_path, settings_path)
print("hook registrations removed")
PY
fi

rm -f "$hooks_dir/herdr-claude-session-title.sh" "$hooks_dir/herdr-claude-session-title.py"
echo "uninstalled"
```

- [ ] **Step 5: Testleri çalıştır, geçtiklerini gör**

Run: `sh tests/test-install.sh`
Expected: `install idempotency: OK`, `uninstall cleanup: OK`, `test-install: OK`

Run: `sh tests/run.sh`
Expected: üç test betiği de koşar, `all tests: OK`

- [ ] **Step 6: Commit**

```bash
git add scripts/install.sh scripts/uninstall.sh tests/test-install.sh
git commit -m "feat: idempotent install and uninstall actions"
```

---

### Task 5: status aksiyonu

**Files:**
- Create: `scripts/status.sh`
- Create: `tests/test-status.sh`

**Interfaces:**
- Consumes: Task 4'ün kurulum yolları ve marker kuralı (`herdr-claude-session-title.sh`).
- Produces: `sh scripts/status.sh` — kurulum durumunu insan-okur satırlarla basar; hiçbir şeyi değiştirmez, her durumda exit 0.

- [ ] **Step 1: Başarısız olacak testi yaz**

`tests/test-status.sh`:

```sh
#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
unset CLAUDE_CONFIG_DIR 2>/dev/null || true
unset HERDR_SOCKET_PATH 2>/dev/null || true
export HERDR_PLUGIN_ROOT="$PWD"
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$HOME/.claude"

out=$(sh scripts/status.sh)
echo "$out" | grep -q "hook script: NOT installed" || fail "expected NOT installed, got: $out"

sh scripts/install.sh >/dev/null
out=$(sh scripts/status.sh)
echo "$out" | grep -q "hook script: installed" || fail "expected installed, got: $out"
echo "$out" | grep -q "SessionStart: registered" || fail "expected SessionStart registered, got: $out"
echo "$out" | grep -q "UserPromptSubmit: registered" || fail "expected UserPromptSubmit registered, got: $out"
echo "$out" | grep -q "Stop: registered" || fail "expected Stop registered, got: $out"

echo "test-status: OK"
```

- [ ] **Step 2: Testi çalıştır, başarısızlığı gör**

Run: `sh tests/test-status.sh`
Expected: FAIL — `scripts/status.sh` henüz yok.

- [ ] **Step 3: status.sh'i yaz**

`scripts/status.sh`:

```sh
#!/bin/sh
# herdr plugin action: prints hook installation status (read-only)
set -eu

claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
hook_sh="$claude_dir/hooks/herdr-claude-session-title.sh"
settings_path="$claude_dir/settings.json"

if [ -x "$hook_sh" ]; then
  echo "hook script: installed ($hook_sh)"
else
  echo "hook script: NOT installed"
fi

if [ -f "$settings_path" ] && command -v python3 >/dev/null 2>&1; then
  SETTINGS_PATH="$settings_path" python3 - <<'PY'
import json
import os

settings = json.load(open(os.environ["SETTINGS_PATH"], encoding="utf-8"))
marker = "herdr-claude-session-title.sh"
for event in ["SessionStart", "UserPromptSubmit", "Stop"]:
    count = sum(
        1
        for entry in settings.get("hooks", {}).get(event, [])
        if isinstance(entry, dict)
        for h in entry.get("hooks", [])
        if isinstance(h, dict) and marker in str(h.get("command", ""))
    )
    status = "registered" if count == 1 else "{} entries".format(count)
    print("{}: {}".format(event, status))
PY
else
  echo "settings.json: not found or python3 missing"
fi

if [ -n "${HERDR_SOCKET_PATH:-}" ] && [ -S "$HERDR_SOCKET_PATH" ]; then
  echo "herdr socket: reachable ($HERDR_SOCKET_PATH)"
else
  echo "herdr socket: not available in this environment"
fi
```

- [ ] **Step 4: Testleri çalıştır, geçtiklerini gör**

Run: `sh tests/test-status.sh`
Expected: `test-status: OK`

Run: `sh tests/run.sh`
Expected: dört test betiği de koşar, `all tests: OK`

- [ ] **Step 5: Commit**

```bash
git add scripts/status.sh tests/test-status.sh
git commit -m "feat: read-only status action"
```

---

### Task 6: README, plugin link ve canlı uçtan uca doğrulama

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: önceki tüm task'lerin çıktıları; kurulu bir herdr (>= 0.7.0) ve Claude Code.

- [ ] **Step 1: README'yi yaz**

`README.md`:

```markdown
# herdr-claude-session-title

Herdr plugin: mirrors the Claude Code session title (set with `/rename`,
or the auto-generated summary) into the herdr pane metadata title.

## How it works

The `install` action registers a small hook script with Claude Code
(`~/.claude/settings.json`, events: SessionStart, UserPromptSubmit, Stop).
On each event the hook reads the session transcript, picks the latest
`custom-title` record (your `/rename`), falls back to the auto summary in
`sessions-index.json`, and reports it to the herdr server over the herdr
socket as pane metadata (`pane.report_metadata`). The pane label is not
touched; the title shows up in herdr's navigator/detail view.

The hook is silent by design: outside herdr, or on any error, it exits 0
without output and never blocks Claude Code (0.5s socket timeout).

## Requirements

- herdr >= 0.7.0 (Linux or macOS)
- Claude Code with hooks support
- python3 on PATH

## Install

    herdr plugin install bcihanc/herdr-claude-session-title
    herdr plugin action invoke bcihanc.claude-session-title.install

Restart any Claude Code session that was already running; hooks are read
at session start.

## Verify

1. Inside herdr, open Claude Code in a pane.
2. Run `/rename my-task-name`, then send any message.
3. Open the herdr navigator: the pane detail shows `my-task-name`.

Check installation state any time:

    herdr plugin action invoke bcihanc.claude-session-title.status

## Uninstall

    herdr plugin action invoke bcihanc.claude-session-title.uninstall
    herdr plugin uninstall bcihanc.claude-session-title

## Development

    sh tests/run.sh        # offline tests, no herdr/Claude needed
    herdr plugin link .    # register the working tree with herdr

Troubleshooting: `herdr plugin log list --plugin bcihanc.claude-session-title`
```

- [ ] **Step 2: Tüm testleri son kez koştur**

Run: `sh tests/run.sh`
Expected: dört test betiği, `all tests: OK`

- [ ] **Step 3: Plugin'i herdr'a link'le ve aksiyonları listele**

Herdr oturumu içinden (kurulu stable herdr ile):

Run: `herdr plugin link "$PWD" && herdr plugin action list --plugin bcihanc.claude-session-title`
Expected: üç aksiyon listelenir: `install`, `uninstall`, `status`. Manifest hatası görülmez.

- [ ] **Step 4: install aksiyonunu gerçek ortamda çalıştır**

Run: `herdr plugin action invoke bcihanc.claude-session-title.install`
Expected: `registered hooks: SessionStart, UserPromptSubmit, Stop` + `installed: ...` çıktısı.

Run: `herdr plugin action invoke bcihanc.claude-session-title.status`
Expected: `hook script: installed`, üç olay için `registered`.

- [ ] **Step 5: Canlı uçtan uca doğrulama (kullanıcı ile birlikte)**

Bu adım insan gözü ister — Can/Cihan doğrular:

1. Herdr içinde yeni bir pane'de `claude` başlat (hook'lar oturum başında okunur; mevcut oturumlar yeniden başlatılmalı).
2. `/rename deneme-adi` yaz, ardından herhangi bir mesaj gönder.
3. Herdr gezgin/detay görünümünde pane'in title'ının `deneme-adi` olduğunu gör.
4. `/rename ikinci-ad` + bir mesaj daha → title'ın güncellendiğini gör.
5. Sorun olursa: `herdr plugin log list --plugin bcihanc.claude-session-title` ve
   `herdr pane read <pane> --source detection --format text` ile teşhis.

Expected: title her rename + etkileşim sonrası güncellenir; Claude Code akışında görünür gecikme/uyarı yoktur.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: readme with install and verification steps"
```
