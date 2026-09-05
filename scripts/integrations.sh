#!/bin/sh
# Install, inspect, or remove every applicable session-title integration.
set -u

usage() {
  echo "usage: integrations.sh install|status|uninstall [claude|codex|omp|hermes ...]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
action=$1
shift
case "$action" in
  install|status|uninstall) ;;
  *) usage ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
plugin_root=${HERDR_PLUGIN_ROOT:-$(dirname "$script_dir")}
export HERDR_PLUGIN_ROOT="$plugin_root"

agent_command() {
  case "$1" in
    claude) echo claude ;;
    codex) echo codex ;;
    omp) echo omp ;;
    hermes) echo hermes ;;
    *) return 1 ;;
  esac
}

integration_script() {
  case "$action:$1" in
    install:claude) echo "$plugin_root/scripts/install-claude.sh" ;;
    status:claude) echo "$plugin_root/scripts/status-claude.sh" ;;
    uninstall:claude) echo "$plugin_root/scripts/uninstall-claude.sh" ;;
    install:codex) echo "$plugin_root/scripts/install-codex.sh" ;;
    status:codex) echo "$plugin_root/scripts/status-codex.sh" ;;
    uninstall:codex) echo "$plugin_root/scripts/uninstall-codex.sh" ;;
    install:omp) echo "$plugin_root/scripts/install-omp.sh" ;;
    status:omp) echo "$plugin_root/scripts/status-omp.sh" ;;
    uninstall:omp) echo "$plugin_root/scripts/uninstall-omp.sh" ;;
    install:hermes) echo "$plugin_root/scripts/install-hermes.sh" ;;
    status:hermes) echo "$plugin_root/scripts/status-hermes.sh" ;;
    uninstall:hermes) echo "$plugin_root/scripts/uninstall-hermes.sh" ;;
    *) return 1 ;;
  esac
}

integration_present() {
  case "$1" in
    claude)
      base=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
      [ -e "$base/herdr-agent-session-title-claude.py" ] ||
        [ -e "$base/herdr-session-title-statusline-state.json" ]
      ;;
    codex)
      base=${CODEX_HOME:-$HOME/.codex}
      [ -e "$base/herdr-agent-session-title-codex.py" ] ||
        [ -e "$base/herdr-session-title-notify-state.json" ]
      ;;
    omp)
      data_home=${XDG_DATA_HOME:-$HOME/.local/share}
      [ -e "$data_home/herdr-agent-session-title/omp-plugin" ] ||
        [ -L "$HOME/.omp/plugins/node_modules/@the-inconvenience-store/herdr-agent-session-title" ]
      ;;
    hermes)
      base=${HERMES_HOME:-$HOME/.hermes}
      [ -e "$base/plugins/herdr-agent-session-title" ] ||
        [ -L "$base/plugins/herdr-agent-session-title" ]
      ;;
  esac
}

available() {
  command_name=$(agent_command "$1") || return 1
  command -v "$command_name" >/dev/null 2>&1
}

for requested in "$@"; do
  agent_command "$requested" >/dev/null || usage
done

selected=""
if [ "$#" -gt 0 ]; then
  for requested in "$@"; do
    case " $selected " in
      *" $requested "*) ;;
      *) selected="$selected $requested" ;;
    esac
  done
else
  for candidate in claude codex omp hermes; do
    if available "$candidate"; then
      selected="$selected $candidate"
    elif [ "$action" != install ] && integration_present "$candidate"; then
      selected="$selected $candidate"
    fi
  done
fi

if [ -z "$selected" ]; then
  echo "no supported agent installations found"
  exit 0
fi

result=0
for target in $selected; do
  echo "== $target =="
  script=$(integration_script "$target") || {
    echo "$target: integration script is unavailable" >&2
    result=1
    continue
  }
  if ! available "$target" && [ "$target" != claude ] && [ "$target" != codex ]; then
    echo "$target: agent command is unavailable; cannot $action integration" >&2
    result=1
    continue
  fi
  if ! sh "$script"; then
    echo "$target: $action failed" >&2
    result=1
  fi
done

exit "$result"
