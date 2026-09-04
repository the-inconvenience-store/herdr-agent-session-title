# herdr-agent-session-title

Herdr plugin: mirrors Claude Code, Codex, and OMP session titles into the
matching herdr agent name.

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

The `install-codex` action registers a Codex `notify` callback for
`agent-turn-complete`. This is Codex's external notification interface, not
its hooks system. The callback uses the notification's exact thread ID,
prefers the persisted custom thread name used by `/rename`, and otherwise
falls back to Codex's extracted title (normally the first prompt).

If another Codex `notify` command is already configured, the installer records
and chains it. Uninstall restores that command without reverting unrelated
changes to `~/.codex/config.toml`.

### OMP

The `install-omp` action links this package through OMP's plugin manager. Its
extension sends the current OMP session name with `agent.rename`. It observes
`/rename` input and briefly waits for OMP to persist the explicit name. After a
completed main-agent turn, it also waits briefly when OMP's generated title is
still being produced.

OMP does not currently expose a session-name-changed extension event, so the
extension uses those two documented lifecycle points instead of OMP internals
or continuous polling. Task and scout subagent sessions do not rename the
containing herdr pane. The extension is silent outside herdr and uses a
0.5-second socket timeout.

## Requirements

- herdr >= 0.7.0 (Linux or macOS)
- Claude Code with custom status-line support, Codex CLI, and/or OMP with
  `session_stop` extension support (tested with OMP 18.1.2)
- python3 on PATH

## Install Claude Code

    herdr plugin install the-inconvenience-store/herdr-agent-session-title
    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.install

Restart any Claude Code session that was already running so it loads the
updated `statusLine` setting. Claude Code requires workspace trust for
status-line commands, and `disableAllHooks` also disables status lines.

## Install Codex

    herdr plugin install the-inconvenience-store/herdr-agent-session-title
    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.install-codex

Restart Codex sessions that were already running so they load the updated
`notify` setting. The title is reported after each completed turn; a `/rename`
therefore appears after the next completed turn.

## Install OMP

    herdr plugin install the-inconvenience-store/herdr-agent-session-title
    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.install-omp

Restart OMP sessions that were already running so they load the extension. The
integration is installed through OMP's user plugin registry, so it follows
OMP's profile and XDG configuration handling.

## Verify

1. Inside herdr, open Claude Code, Codex, or OMP in a pane.
2. Run `/rename my-task-name`. In OMP, the herdr name updates directly; Claude
   Code and Codex report it on their next callback.
3. To verify OMP's generated title, start a fresh session, send a normal prompt,
   and let the first turn complete.
4. Open the herdr navigator and confirm that the matching agent uses the session
   title.

Check installation state any time:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.status

For Codex:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.status-codex

For OMP:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.status-omp

## Uninstall

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.uninstall
    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.uninstall-codex
    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.uninstall-omp
    herdr plugin uninstall the-inconvenience-store.herdr-agent-session-title

## Development

    sh tests/run.sh        # offline tests, no herdr/Claude needed
    herdr plugin link .    # register the working tree with herdr

Troubleshooting: `herdr plugin log list --plugin the-inconvenience-store.herdr-agent-session-title`
