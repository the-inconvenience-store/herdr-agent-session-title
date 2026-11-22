# herdr-agent-session-title

Herdr plugin: mirrors Claude Code, Codex, OMP, Hermes, and opencode session
titles into the matching herdr agent name.

## How it works

### Claude Code

The `install` action registers a Claude Code `statusLine` command. It does not
install Claude hooks. Claude passes the explicit `session_name` from `/rename`,
plus the session ID and transcript path, to this command. When no explicit name
is present, the command reads the latest `ai-title` from the transcript, with
legacy `sessions-index.json` summaries as a last resort.

If another Claude status-line command is already configured, the installer
records it and the wrapper relays its output unchanged. Uninstall restores the
original command without reverting unrelated changes to
`~/.claude/settings.json`.

The wrapper normalizes the selected title to herdr's agent-name format
(lowercase letters, digits, and hyphens, up to 32 characters) and sends it
with `agent.rename`. It renames the agent, not the pane. It is silent outside
herdr and uses a 0.5-second socket timeout.

### Codex

The Codex integration registers a `notify` callback for
`agent-turn-complete`. This is Codex's external notification interface, not
its hooks system. The callback uses the notification's exact thread ID,
prefers the persisted custom thread name used by `/rename`, and otherwise
falls back to Codex's extracted title (normally the first prompt).

If another Codex `notify` command is already configured, the installer records
and chains it. Uninstall restores that command without reverting unrelated
changes to `~/.codex/config.toml`.

### OMP

The OMP integration installs a self-contained package through OMP's plugin
manager. Its extension mirrors the current OMP session name with `agent.rename`,
including resumed sessions, `/rename`, generated titles, and RPC name changes.

OMP does not currently expose a session-name-changed extension event. The
extension checks the public session-name API once per second for the lifetime
of an interactive or RPC session and sends a rename only when the title changes.
Unlike a short watch after input or turn completion, this also catches slow
title generation and `/rename` card generation that finish more than five
seconds later. Task and scout subagent runtimes do not rename the containing
herdr pane. The extension is silent outside herdr, stops watching on session
shutdown, and uses a 0.5-second socket timeout.

### Hermes

The Hermes integration copies and enables a profile-local Hermes plugin.
It reads persisted titles through Hermes's `SessionDB` and sends them with
`agent.rename`. Existing titles are reported when a session starts or resumes.
For new sessions, the plugin briefly watches after `pre_llm_call` to observe
Hermes's immediate derived title and its asynchronous LLM-generated upgrade.

Hermes does not currently expose a public session-title-changed plugin hook.
The integration therefore observes the documented `pre_command` hook for
`/title`, then briefly waits for Hermes to persist an accepted title. It never
patches Hermes internals or continuously polls the session database.
Subagents and non-interactive platforms cannot rename the containing herdr
pane.

The plugin is silent outside herdr. It normalizes titles to herdr's agent-name
format and uses a 0.5-second socket timeout.

### opencode

The opencode integration installs a small TUI plugin into opencode's global
config directory (`${XDG_CONFIG_HOME:-~/.config}/opencode/herdr-agent-session-title/`)
and lists it in `cli.json`. Plugins listed in `cli.json` run locally in the TUI
process, which is the only process that knows which herdr pane it belongs to;
the shared opencode server cannot attribute a session to a pane. The installer
merges one entry into an existing `cli.json`, keeps every other setting and
plugin, and backs the file up to `cli.json.bak-herdr-agent-session-title`.
Uninstall removes only this plugin's entry and directory.

The plugin reads the title of the session shown in the pane from opencode's
session store and sends it with `agent.rename`. A new opencode session has no
title until one is generated or set, so an untitled session leaves the herdr
name unchanged. The plugin also reacts to opencode's `session.renamed` event,
so `Rename session` (`ctrl+r`) lands immediately; the session shown in the pane
is re-checked once per second, which picks up resumed sessions, switching
sessions, and titles set by other means. When a subagent (child) session is
shown, the title of its root session is used. Being a TUI plugin, it applies to
the interactive TUI only. It is silent outside herdr, never throws into
opencode, and uses the same 0.5-second socket timeout as the other
integrations.

## Requirements

- herdr >= 0.7.0 (Linux or macOS)
- Claude Code with custom status-line support, Codex CLI, OMP with extension
  context timers and runtime-mode support, Hermes Agent with plugin hooks, and/or
  opencode 2.x with `cli.json` TUI plugin support (tested with OMP 18.12.6,
  Hermes Agent 0.20.6, and opencode 2.3.2)
- python3 on PATH

## Install

    herdr plugin install the-inconvenience-store/herdr-agent-session-title

During a GitHub plugin install, Herdr runs the manifest's reviewed build
command. This plugin uses that lifecycle to detect `claude`, `codex`, `omp`,
`hermes`, and `opencode` on `PATH` and install every available integration automatically.
Local `herdr plugin link` intentionally does not run build commands.

The same bulk action remains available for repairs and for agents installed
after the Herdr plugin:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.install

Herdr plugin actions do not accept positional arguments. The action therefore
repairs every detected supported agent. From a source checkout, developers can
target a subset directly:

    sh scripts/integrations.sh install codex omp claude opencode

Restart already-running agent sessions after installation. Claude Code requires
workspace trust for status-line commands, and `disableAllHooks` also disables
status lines. Hermes plugins are profile-local; `$HERMES_HOME` selects a
non-default profile.

## Verify

1. Inside herdr, open Claude Code, Codex, OMP, Hermes, or opencode in a pane.
2. Run `/rename my-task-name` in Claude Code, Codex, or OMP. Run
   `/title my-task-name` in Hermes. In opencode, run the **Rename session**
   command (`ctrl+r`). OMP, Hermes, and opencode update the herdr name
   directly; Claude Code and Codex report it on their next callback.
3. To verify a generated title, start a fresh OMP or Hermes session, send a
   normal prompt, and let the first turn complete.
4. Open the herdr navigator and confirm that the matching agent uses the
   session title.

Check all detected or configured integration states:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.status

## Uninstall

Remove all detected or configured agent integrations before removing the Herdr
plugin:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.uninstall
    herdr plugin uninstall the-inconvenience-store/herdr-agent-session-title

## Development

    sh tests/run.sh        # offline tests, no herdr/Claude needed
    herdr plugin link .    # register the working tree with herdr

Troubleshooting: `herdr plugin log list --plugin the-inconvenience-store.herdr-agent-session-title`
