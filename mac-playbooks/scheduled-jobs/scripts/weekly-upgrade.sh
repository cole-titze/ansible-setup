#!/bin/bash
# Weekly homelab upgrade + nhl-odds security pass, started by launchd
# (com.coletitze.weekly-upgrade) on Sundays at 10:00 CT. Runs Claude Code headless on this Mac,
# so it has the Mac's kubectl, gh, ansible, docker, dotnet, ssh keys (helm runs on node01) and the skills in
# ~/.claude/skills. The instructions are in weekly-upgrade-prompt.md next to this script.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"
# nvm's default Node (nhl-odds frontend checks), if installed
# shellcheck source=/dev/null
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1

PROMPT_FILE="$SCRIPT_DIR/weekly-upgrade-prompt.md"
STAMP="$(date +%Y-%m-%d)"
LOG="$LOG_DIR/weekly-upgrade-$STAMP.log"
SUMMARY="$LOG_DIR/weekly-upgrade-$STAMP-summary.md"

cd "$HOME/source/repos" || exit 1
start_cluster_env 16443

{
  echo "== Weekly upgrade $(date '+%Y-%m-%d %H:%M:%S')"
  # Unattended: no one is there to approve tool calls. The prompt carries the safety rules.
  # stream-json writes each step to the log as it happens, so a stuck run shows where it stopped.
  claude -p "$(cat "$PROMPT_FILE")

Write the final summary to $SUMMARY as well as printing it." \
    --permission-mode bypassPermissions \
    --add-dir "$HOME/.claude/skills" \
    --add-dir "$ANSIBLE_FILES_PATH" \
    --output-format stream-json --verbose
} >>"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  notify "Weekly homelab upgrade FAILED" "Exit $status. See $LOG"
  discord_post "❌ Weekly upgrade FAILED (exit $status)" "Log: $LOG" "$SUMMARY"
else
  notify "Weekly homelab upgrade done" "Summary: $SUMMARY"
  discord_post "🛠️ Weekly upgrade done" "$(cat "$SUMMARY" 2>/dev/null || echo "No summary written. Log: $LOG")" "$SUMMARY"
fi

find "$LOG_DIR" -name 'weekly-upgrade-*' -mtime +90 -delete
exit $status
