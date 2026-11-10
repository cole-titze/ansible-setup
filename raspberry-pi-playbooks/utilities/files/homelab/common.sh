# Shared by the backup Pi's homelab jobs (source it; not run on its own). Installed to
# /usr/local/lib/homelab/common.sh by backup-node-jobs.yml. The Pi version of the Mac's
# mac-playbooks/scheduled-jobs/scripts/common.sh.
# shellcheck shell=bash

LOG_DIR=/var/log/homelab
WEBHOOK_FILE=/etc/homelab/discord-webhook
mkdir -p "$LOG_DIR"

# discord_post <title> <text> [file]: posts to the homelab alerts channel (same webhook as
# Alertmanager). The URL is in a root-only file the playbook writes from alerting_vars.yml.
# Text is cut to fit Discord's 2000-character limit; the optional file is attached whole.
discord_post() {
  local title=$1 text=$2 file=${3:-} url payload
  url=$(cat "$WEBHOOK_FILE" 2>/dev/null)
  if [ -z "$url" ]; then
    echo "No Discord webhook in $WEBHOOK_FILE; re-run backup-node-jobs.yml" >&2
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
    args+=(--form-string "payload_json=$payload" -F "files[0]=@$file")
  else
    args+=(-H "Content-Type: application/json" -d "$payload")
  fi
  case $(curl "${args[@]}" "$url") in
    2??) return 0 ;;
    *) echo "Discord post failed: $title" >&2; return 1 ;;
  esac
}
