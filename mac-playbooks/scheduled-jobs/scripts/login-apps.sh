#!/bin/bash
# Runs once at login (launchd RunAtLoad). Starts Ollama, which the nhl-odds assistant calls over the
# network, and opens a Terminal window running Claude Code Remote Control in ~/source/repos.
set -u

open -a Ollama

# Skip if one is already running (the playbook loads this job right away, not just at login)
ps -axo args= | grep -qE '^(/[^ ]*/)?claude rc( |$)' && exit 0

# Terminal runs a .command file in a login shell
cmd_file="$HOME/Library/Application Support/homelab/claude-rc.command"
mkdir -p "$(dirname "$cmd_file")"
cat >"$cmd_file" <<'CMD'
#!/bin/zsh -l
cd "$HOME/source/repos" && exec "$HOME/.local/bin/claude" rc
CMD
chmod 755 "$cmd_file"
open -a Terminal "$cmd_file"
