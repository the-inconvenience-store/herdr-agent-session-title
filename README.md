# herdr-agent-session-title

Herdr plugin: mirrors Claude Code and Codex session titles into the matching
herdr agent name.

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

The wrapper sends the selected title to the herdr server with `agent.rename`.
It is silent outside herdr and uses a 0.5-second socket timeout.

### Codex

The `install-codex` action registers a Codex `notify` callback for
`agent-turn-complete`. This is Codex's external notification interface, not
its hooks system. The callback uses the notification's exact thread ID,
prefers the persisted custom thread name used by `/rename`, and otherwise
falls back to Codex's extracted title (normally the first prompt).

If another Codex `notify` command is already configured, the installer records
and chains it. Uninstall restores that command without reverting unrelated
changes to `~/.codex/config.toml`.

## Requirements

- herdr >= 0.7.0 (Linux or macOS)
- Claude Code with custom status-line support and/or Codex CLI
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

## Verify

1. Inside herdr, open Claude Code or Codex in a pane.
2. Run `/rename my-task-name`, then send any message.
3. Open the herdr navigator: the agent is named `my-task-name`.

Check installation state any time:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.status

For Codex:

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.status-codex

## Uninstall

    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.uninstall
    herdr plugin action invoke the-inconvenience-store.herdr-agent-session-title.uninstall-codex
    herdr plugin uninstall the-inconvenience-store.herdr-agent-session-title

## Development

    sh tests/run.sh        # offline tests, no herdr/Claude needed
    herdr plugin link .    # register the working tree with herdr

Troubleshooting: `herdr plugin log list --plugin the-inconvenience-store.herdr-agent-session-title`
