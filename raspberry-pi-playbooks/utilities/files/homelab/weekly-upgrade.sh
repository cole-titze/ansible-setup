#!/bin/bash
# Weekly homelab upgrade + nhl-odds security pass on the backup Pi, started by
# homelab-weekly-upgrade.timer on Sundays at 10:00 CT (backup-node-weekly-upgrade.yml; moved from the
# Mac's launchd job). Runs Claude Code headless as pi with weekly-upgrade-prompt.md, with pi's
# kubectl, gh, ansible, ssh keys and the skills in ~pi/.claude/skills, then posts the summary to
# Discord. The alert agent holds new alerts while this runs (its upgrades fire alerts).
set -uo pipefail
. /usr/local/lib/homelab/common.sh

PI_HOME=/home/pi
export KUBECONFIG=$PI_HOME/.kube/config
export PATH="$PI_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
PROMPT_FILE=/usr/local/lib/homelab/weekly-upgrade-prompt.md
TOKEN_FILE=/etc/homelab/claude-oauth-token
STAMP="$(date +%Y-%m-%d)"
LOG="$LOG_DIR/weekly-upgrade-$STAMP.log"
# pi writes the summary; it's copied next to the log afterwards
SUMMARY_DIR=$PI_HOME/homelab
SUMMARY="$SUMMARY_DIR/weekly-upgrade-$STAMP-summary.md"

install -d -o pi -g pi -m 0755 "$SUMMARY_DIR"
CLAUDE_CODE_OAUTH_TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)
export CLAUDE_CODE_OAUTH_TOKEN
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  discord_post "❌ Weekly upgrade FAILED" "No Claude token in $TOKEN_FILE on the backup Pi."
  exit 1
fi

cd "$PI_HOME/source/repos" || exit 1
{
  echo "== Weekly upgrade $(date '+%Y-%m-%d %H:%M:%S')"
  # Unattended: no one is there to approve tool calls. The prompt carries the safety rules.
  # stream-json writes each step to the log as it happens, so a stuck run shows where it stopped.
  # runuser keeps the environment (token, KUBECONFIG, PATH) and sets HOME to pi's.
  runuser -u pi -- claude -p "$(cat "$PROMPT_FILE")

Write the final summary to $SUMMARY as well as printing it." \
    --permission-mode bypassPermissions \
    --output-format stream-json --verbose
} >>"$LOG" 2>&1
status=$?
[ -s "$SUMMARY" ] && cp "$SUMMARY" "$LOG_DIR/"

if [ $status -ne 0 ]; then
  discord_post "❌ Weekly upgrade FAILED (exit $status)" "Log: $(hostname):$LOG" "$SUMMARY"
else
  # Only the TL;DR (above "## Details") goes in the message; the whole summary is attached.
  if [ -s "$SUMMARY" ]; then
    tldr=$(awk '/^##[[:space:]]*Details/ { exit } { print }' "$SUMMARY")
  else
    tldr="No summary written. Log: $(hostname):$LOG"
  fi
  discord_post "🛠️ Weekly upgrade done" "$tldr" "$SUMMARY"
fi

find "$LOG_DIR" "$SUMMARY_DIR" -maxdepth 1 -name 'weekly-upgrade-*' -mtime +90 -delete
exit $status
