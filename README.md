# herdr-agent-session-title

Herdr plugin: mirrors Claude Code, Codex, OMP, and Hermes session titles into
the matching herdr agent name.

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
manager. Its
extension sends the current OMP session name with `agent.rename`. It observes
`/rename` input and briefly waits for OMP to persist the explicit name. After a
completed main-agent turn, it also waits briefly when OMP's generated title is
still being produced.

OMP does not currently expose a session-name-changed extension event, so the
extension uses those two documented lifecycle points instead of OMP internals
or continuous polling. Task and scout subagent sessions do not rename the
containing herdr pane. The extension is silent outside herdr and uses a
0.5-second socket timeout.

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

## Requirements

- herdr >= 0.7.0 (Linux or macOS)
- Claude Code with custom status-line support, Codex CLI, OMP with
  `session_stop` extension support, and/or Hermes Agent with plugin hooks
  (tested with OMP 18.1.2 and Hermes Agent 0.20.6)
- python3 on PATH

## Install

    herdr plugin install the-inconvenience-store/herdr-agent-session-title

During a GitHub plugin install, Herdr runs the manifest's reviewed build
command. This plugin uses that lifecycle to detect `claude`, `codex`, `omp`,
and `hermes` on `PATH` and install every available integration automatically.
Local `herdr plugin link` intentionally does not run build commands.

The same bulk action remains available for repairs and for agents installed
after the Herdr plugin:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.install

Herdr plugin actions do not accept positional arguments. The action therefore
repairs every detected supported agent. From a source checkout, developers can
target a subset directly:

    sh scripts/integrations.sh install codex omp claude

Restart already-running agent sessions after installation. Claude Code requires
workspace trust for status-line commands, and `disableAllHooks` also disables
status lines. Hermes plugins are profile-local; `$HERMES_HOME` selects a
non-default profile.

## Verify

1. Inside herdr, open Claude Code, Codex, OMP, or Hermes in a pane.
2. Run `/rename my-task-name` in Claude Code, Codex, or OMP. Run
   `/title my-task-name` in Hermes. OMP and Hermes update the herdr name
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
