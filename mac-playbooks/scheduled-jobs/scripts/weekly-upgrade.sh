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

# macOS Local Network privacy: under launchd only Apple's binaries (ssh, curl) may reach 10.42.0.x;
# kubectl gets "no route to host". Tunnel the K3s API through localhost with ssh and point a
# copy of the kubeconfig at it (K3s's API cert covers 127.0.0.1).
KUBE_TUNNEL_PORT=16443
ssh -i "$HOME/.ssh/node01" -o BatchMode=yes -o ExitOnForwardFailure=yes -N \
  -L "$KUBE_TUNNEL_PORT:127.0.0.1:6443" pi@10.42.0.20 >>"$LOG" 2>&1 &
tunnel_pid=$!
KUBECONFIG="$(mktemp -t weekly-kubeconfig)"
export KUBECONFIG
trap 'kill $tunnel_pid 2>/dev/null; rm -f "$KUBECONFIG"' EXIT
sed "s|server: https://10.42.0.20:6443|server: https://127.0.0.1:$KUBE_TUNNEL_PORT|" "$HOME/.kube/config" >"$KUBECONFIG"
for _ in $(seq 1 15); do nc -z 127.0.0.1 "$KUBE_TUNNEL_PORT" 2>/dev/null && break; sleep 1; done

{
  echo "== Weekly upgrade $(date '+%Y-%m-%d %H:%M:%S')"
  # Unattended: no one is there to approve tool calls. The prompt carries the safety rules.
  # stream-json writes each step to the log as it happens, so a stuck run shows where it stopped.
  claude -p "$(cat "$PROMPT_FILE")

Write the final summary to $SUMMARY as well as printing it." \
    --permission-mode bypassPermissions \
    --add-dir "$HOME/.claude/skills" \
    --add-dir "$HOME/source/ansible-files" \
    --output-format stream-json --verbose
} >>"$LOG" 2>&1
status=$?

if [ $status -ne 0 ]; then
  notify "Weekly homelab upgrade FAILED" "Exit $status. See $LOG"
else
  notify "Weekly homelab upgrade done" "Summary: $SUMMARY"
fi

find "$LOG_DIR" -name 'weekly-upgrade-*' -mtime +90 -delete
exit $status
