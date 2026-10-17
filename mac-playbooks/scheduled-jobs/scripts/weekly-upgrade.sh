#!/bin/bash
# Weekly homelab upgrade + nhl-odds security pass, started by launchd
# (com.coletitze.weekly-upgrade) on Sundays at 10:00 CT. Runs Claude Code headless on this Mac,
# so it has the Mac's kubectl, gh, ansible, docker, dotnet, ssh keys (helm runs on node01) and the skills in
# ~/.claude/skills. The instructions are in weekly-upgrade-prompt.md next to this script.
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
# nvm's default Node (nhl-odds frontend checks), if installed
# shellcheck source=/dev/null
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/weekly-upgrade-prompt.md"
LOG_DIR="$HOME/Library/Logs/homelab"
STAMP="$(date +%Y-%m-%d)"
LOG="$LOG_DIR/weekly-upgrade-$STAMP.log"
SUMMARY="$LOG_DIR/weekly-upgrade-$STAMP-summary.md"
mkdir -p "$LOG_DIR"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

cd "$HOME/source/repos" || exit 1

{
  echo "== Weekly upgrade $(date '+%Y-%m-%d %H:%M:%S')"
  # Unattended: no one is there to approve tool calls. The prompt carries the safety rules.
  claude -p "$(cat "$PROMPT_FILE")

Write the final summary to $SUMMARY as well as printing it." \
    --permission-mode bypassPermissions \
    --add-dir "$HOME/.claude/skills" \
    --add-dir "$HOME/source/ansible-files"
} >>"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  notify "Weekly homelab upgrade FAILED" "Exit $status. See $LOG"
else
  notify "Weekly homelab upgrade done" "Summary: $SUMMARY"
fi

find "$LOG_DIR" -name 'weekly-upgrade-*' -mtime +90 -delete
exit $status
