# Shared by the launchd job scripts (source it; not run on its own).
# shellcheck shell=bash

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES   # Python fork crashes on macOS, see macbook-setup.md
# The jobs run outside the repo, so ansible.cfg (and its vault_password_file) isn't read
export ANSIBLE_VAULT_PASSWORD_FILE="$HOME/source/repos/ansible-setup/vault-pass.sh"

LOG_DIR="$HOME/Library/Logs/homelab"
mkdir -p "$LOG_DIR"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

# discord_post <title> <text> [file]: posts to the homelab alerts channel (same webhook as
# Alertmanager). The URL is in the login keychain (scheduled-jobs.yml copies it there from the
# vault), since launchd's bash can't read the vaulted file in iCloud. Text is cut to fit Discord's
# 2000-character limit; the optional file is attached whole. Falls back to a macOS notification.
discord_post() {
  local title=$1 text=$2 file=${3:-} url payload
  url=$(security find-generic-password -s homelab-discord-webhook -a homelab -w 2>/dev/null)
  if [ -z "$url" ]; then
    notify "$title" "No Discord webhook in the keychain; re-run scheduled-jobs.yml"
    return 1
  fi
  payload=$(TITLE="$title" TEXT="$text" python3 -c '
import json, os
body = os.environ["TEXT"]
if len(body) > 1850:
    body = body[:1850].rsplit("\n", 1)[0] + "\n... (full text attached)"
print(json.dumps({"content": f"**{os.environ['"'"'TITLE'"'"']}**\n{body}"[:2000]}))')
  local args=(-s -o /dev/null -w "%{http_code}" -m 30)
  if [ -n "$file" ] && [ -f "$file" ]; then
    args+=(-F "payload_json=$payload" -F "files[0]=@$file")
  else
    args+=(-H "Content-Type: application/json" -d "$payload")
  fi
  case $(curl "${args[@]}" "$url") in
    2??) [ -n "${POLL_LOG:-}" ] && echo "$(date '+%F %T') posted to Discord: $title" >>"$POLL_LOG"; return 0 ;;
    *) notify "$title" "Discord post failed. ${text:0:120}"; return 1 ;;
  esac
}

# start_cluster_env: sets up what an unattended Claude session needs to run kubectl and the
# playbooks; cleans up on exit. Call once, after LOG is set.
# - macOS Local Network privacy: under launchd only Apple's binaries (ssh, curl) may reach
#   10.42.0.x; kubectl gets "no route to host". Tunnel the K3s API through localhost with ssh and
#   point a copy of the kubeconfig at it (K3s's API cert covers 127.0.0.1).
# - The playbooks' vars live in iCloud (~/source/ansible-files), which macOS TCC blocks for
#   Claude's Bash under launchd. Ansible's own Python can read it, so copy vars/ (decrypted, password
#   from the login keychain) to a private temp dir; the cluster playbooks read ANSIBLE_FILES_PATH.
start_cluster_env() {
  local port=$1
  ssh -i "$HOME/.ssh/node01" -o BatchMode=yes -o ExitOnForwardFailure=yes -N \
    -L "$port:127.0.0.1:6443" pi@10.42.0.20 >>"$LOG" 2>&1 &
  CLUSTER_TUNNEL_PID=$!
  KUBECONFIG="$(mktemp -t homelab-kubeconfig)"
  ANSIBLE_FILES_PATH="$(mktemp -d -t homelab-ansible-files)"
  export KUBECONFIG ANSIBLE_FILES_PATH
  trap 'kill $CLUSTER_TUNNEL_PID 2>/dev/null; rm -f "$KUBECONFIG"; rm -rf "$ANSIBLE_FILES_PATH"' EXIT
  sed "s|server: https://10.42.0.20:6443|server: https://127.0.0.1:$port|" "$HOME/.kube/config" >"$KUBECONFIG"
  for _ in $(seq 1 15); do nc -z 127.0.0.1 "$port" 2>/dev/null && break; sleep 1; done
  # Time-limited: a pending macOS privacy prompt for iCloud Drive blocks the read forever
  if ! perl -e 'alarm shift; exec @ARGV' 180 ansible localhost -m ansible.builtin.copy \
    -a "src=$HOME/source/ansible-files/vars dest=$ANSIBLE_FILES_PATH/ mode=0600 directory_mode=0700" >>"$LOG" 2>&1; then
    notify "Homelab job" "Couldn't copy the ansible vars; playbooks will fail. See $LOG"
  fi
}
