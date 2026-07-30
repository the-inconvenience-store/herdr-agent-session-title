# herdr-agent-session-title

Herdr plugin: mirrors Claude Code and Codex session titles into the herdr
pane metadata title.

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

The wrapper reports the selected title to the herdr server as pane metadata
(`pane.report_metadata`). It is silent outside herdr and uses a 0.5-second
socket timeout.

### Codex

The `install-codex` action registers a Codex `notify` callback for
`agent-turn-complete`. This is Codex's external notification interface, not
its hooks system. The callback uses the notification's exact thread ID and
reports the explicit `/rename` name when present, otherwise Codex's extracted
title (normally the first prompt).

If another Codex `notify` command is already configured, the installer records
and chains it. Uninstall restores that command without reverting unrelated
changes to `~/.codex/config.toml`.

## Requirements

- herdr >= 0.7.0 (Linux or macOS)
- Claude Code with custom status-line support and/or Codex CLI
- python3 on PATH

## Install Claude Code

    herdr plugin install bcihanc/herdr-claude-session-title
    herdr plugin action invoke bcihanc.claude-session-title.install

Restart any Claude Code session that was already running so it loads the
updated `statusLine` setting. Claude Code requires workspace trust for
status-line commands, and `disableAllHooks` also disables status lines.

## Install Codex

    herdr plugin install bcihanc/herdr-claude-session-title
    herdr plugin action invoke bcihanc.claude-session-title.install-codex

Restart Codex sessions that were already running so they load the updated
`notify` setting. The title is reported after each completed turn; a `/rename`
therefore appears after the next completed turn.

## Verify

1. Inside herdr, open Claude Code or Codex in a pane.
2. Run `/rename my-task-name`, then send any message.
3. Open the herdr navigator: the pane detail shows `my-task-name`.

Check installation state any time:

    herdr plugin action invoke bcihanc.claude-session-title.status

For Codex:

    herdr plugin action invoke bcihanc.claude-session-title.status-codex

## Uninstall

    herdr plugin action invoke bcihanc.claude-session-title.uninstall
    herdr plugin action invoke bcihanc.claude-session-title.uninstall-codex
    herdr plugin uninstall bcihanc.claude-session-title

## Development

    sh tests/run.sh        # offline tests, no herdr/Claude needed
    herdr plugin link .    # register the working tree with herdr

Troubleshooting: `herdr plugin log list --plugin bcihanc.claude-session-title`
