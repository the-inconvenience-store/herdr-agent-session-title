# herdr-agent-session-title

Herdr plugin: mirrors Claude Code and Codex session titles into the herdr
pane metadata title.

## How it works

### Claude Code

The `install` action registers a small hook script with Claude Code
(`~/.claude/settings.json`, events: SessionStart, UserPromptSubmit, Stop).
On each event the hook reads the session transcript, picks the latest
`custom-title` record (your `/rename`), falls back to the latest `ai-title`
record (Claude Code's auto-generated session name; legacy
`sessions-index.json` summaries are a last resort), and reports it to the
herdr server over the herdr socket as pane metadata
(`pane.report_metadata`). The pane label is not
touched; the title shows up in herdr's navigator/detail view.

The hook is silent by design: outside herdr, or on any error, it exits 0
without output and never blocks Claude Code (0.5s socket timeout).

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
- Claude Code with hooks support and/or Codex CLI
- python3 on PATH

## Install Claude Code

    herdr plugin install bcihanc/herdr-claude-session-title
    herdr plugin action invoke bcihanc.claude-session-title.install

Restart any Claude Code session that was already running; hooks are read
at session start.

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
