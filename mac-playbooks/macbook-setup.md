# MacBook Setup
Runbook for setting up a fresh MacBook, written so an agent (Claude Code) can work through it top to bottom.
Some day I'd like a full playbook like Jeff Geerling's [mac-dev-playbook](https://github.com/geerlingguy/mac-dev-playbook); for now this lists what to install and iCloud holds the rest.

## Start here (new Mac)
Nothing needs to be installed first; Claude Code does the rest.
1. Sign in with your Apple ID, turn on iCloud Drive, and let `ansible-files` finish downloading. In Finder, right-click it → **Keep Downloaded**.
2. Open Terminal and install Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`. Then open a new Terminal, run `claude`, and log in.
3. Tell it: *Set up this Mac by following https://raw.githubusercontent.com/cole-titze/ansible-setup/main/mac-playbooks/macbook-setup.md*
4. When it's done, run `/update-mac` to bring everything up to date (the runbook links the Claude skills in section 6).

Rules for the agent:
- Skip anything already installed, and report what was installed vs skipped at the end.
- Prefer Homebrew casks. If a cask name fails, check `brew search <name>` before falling back to the vendor download.
- Steps marked **(manual)** need the user (GUI login, App Store, permissions); list them for the user instead of attempting them.

## 1. Base tools
```bash
xcode-select --install   # git, make, clang
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh libomp mas   # libomp: LightGBM/XGBoost/torch in nhl-odds; mas: App Store updates for update-mac
gh auth login            # (manual)
```

## 2. iCloud files and keys
`ansible-files` in iCloud holds secrets, cluster vars, and Mac backups (outside any git repo). Wait for iCloud Drive to finish syncing first **(manual)**.
```bash
mkdir -p ~/source/repos
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/ansible-files ~/source/ansible-files
```
Restore from the newest `~/source/ansible-files/backups/macbook/backup_*/` (written by `mac-playbooks/backup/macbook/macbook-backup.yml`):
- `ssh/` → `~/.ssh`, then `chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*`
- `kube/` → `~/.kube`
- `claude/` → `~/.claude` (Claude Code settings and per-project memories; skills come from the claude-skills repo in step 6). Copy it before the first Claude Code session so the memories are picked up.

## 3. Apps
```bash
brew install --cask docker-desktop visual-studio-code jump-desktop-connect claude raspberry-pi-imager
```
- **Docker Desktop**: local nhl-odds compose; its bundled `kubectl` (`/usr/local/bin/kubectl`) is the one used for the K3s cluster.
- **Jump Desktop Connect**: remote access into this Mac. Sign in and grant Screen Recording + Accessibility **(manual)**.
- **WireGuard**: Mac App Store only **(manual)**. Import the tunnels from `~/source/ansible-files/backups/vpn/wireguard-backup.tar.gz`.
- **Claude Code CLI**: already installed in **Start here**; if not, `curl -fsSL https://claude.ai/install.sh | bash` (installs to `~/.local/bin/claude`).

## 4. Dev toolchains
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
nvm install --lts                     # nhl-odds frontend (CI uses Node 22+)
brew install uv                       # manages Python versions, Ansible and project venvs
uv python install 3.14 3.15           # 3.15: the nhl-odds Dockerfile's minor; 3.14: Ansible until ansible-core supports 3.15
uv tool update-shell                  # puts ~/.local/bin (uv tools) on PATH; open a new shell after
```
- **.NET 10 SDK** (nhl-odds targets net10.0): `brew install --cask dotnet-sdk`. It runs Microsoft's installer, so it asks for your password **(manual)**.
- Python comes only from uv: don't install python.org or Homebrew Python. Use the newest stable minor in `uv python list --managed-python` for the nhl-odds venv (match its Dockerfile). The `update-mac` skill keeps Pythons, Ansible and the venvs current.

## 5. Ansible (homelab control machine)
```bash
uv tool install --python 3.14 --with-executables-from ansible-core ansible
echo 'export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES' >> ~/.zprofile   # prevents Python fork crashes on macOS
```
Check that `command -v ansible` is `~/.local/bin/ansible`. Then clone this repo into `~/source/repos/ansible-setup` and follow its README to install the roles and collections.

The vars files in `~/source/ansible-files/vars` are ansible-vault encrypted. `ansible.cfg` reads the password from the login keychain through `vault-pass.sh`, so put it there once **(manual)**: copy it from Apple Passwords (entry "Ansible vault"), then run this and paste it at the prompt (keeps it out of shell history):
```bash
security add-generic-password -a "$USER" -s ansible-vault -l "Ansible vault (ansible-files/vars)" -w
cd ~/source/repos/ansible-setup && ansible-vault view ~/source/ansible-files/vars/cluster_vars.yml >/dev/null && echo OK
```
Edit a vars file with `ansible-vault edit <file>`, never a text editor (it would save it unencrypted or corrupt it). The Saturday restore drill (6b) checks the keychain password still opens all of them.

## 6. Repos and Claude skills
Clone into `~/source/repos`: `ansible-setup`, `claude-skills`, `nhl-odds`, `retirement-calculator`, `containers`, and the `ansible-role-*` repos.
Then run the `mac-setup` skill from `claude-skills` to link skills into `~/.claude/skills`.
For nhl-odds, follow its `CLAUDE.md` (`npm install` in `frontend/`, `python -m game_predictor.libomp`), but create the venv with uv on the Dockerfile's Python minor so it picks up patch releases automatically:
```bash
uv venv --managed-python --python 3.15 .venv
VIRTUAL_ENV=$PWD/.venv uv pip install -r game_predictor/requirements.txt -r game_predictor/requirements-experimental.txt
```

## 6b. Scheduled jobs (main Mac only)
Run on the one Mac that keeps the iCloud backups (only one, or the jobs run twice). No agents (headless Claude, Remote Control) run on the Mac, and nothing on the backup Pi can run anything on it: the alert agent, weekly upgrade and Remote Control live on the backup Pi (`raspberry-pi-playbooks/utilities/backup-node-*.yml`).

Before installing, check what the jobs need:
- **Vars files**: `ls ~/source/ansible-files/vars` shows `cluster_vars.yml`, `nhl_vars.yml`, `retirement_vars.yml` and `alerting_vars.yml`. They come down with iCloud (section 2), so nothing to restore by hand. If one is missing, iCloud hasn't finished syncing; wait.
- **Vault password** in the login keychain (section 5): `cd ~/source/repos/ansible-setup && ansible-vault view ~/source/ansible-files/vars/cluster_vars.yml >/dev/null && echo OK`.
- **Keys**: `~/.ssh` restored (section 2). The nightly backup pulls from the backup Pi with `~/.ssh/backuppi_offsite`: `/usr/bin/rsync --list-only -e "ssh -i ~/.ssh/backuppi_offsite -o BatchMode=yes" pi@10.42.0.3:nhl-odds/SHA256SUMS` lists the file.
- **Docker Desktop** installed for the restore drill (it starts it if it's closed).

Install the jobs:
```bash
cd ~/source/repos/ansible-setup && ansible-playbook mac-playbooks/scheduled-jobs/scheduled-jobs.yml
```
It installs these launchd LaunchAgents that run as you, with your tools and keys, and posts results to Discord (the webhook is copied into the login keychain):
- `com.coletitze.nightly-backup`: daily 4:30, runs `mac-playbooks/backup/scripts/Backup.sh`: copies the backup Pi's nhl-odds dumps, Grafana DBs and Claude memory (pulled off the cluster at 4:00) into iCloud, checks them against the Pi's `SHA256SUMS`, then backs up the Mac itself.
- `com.coletitze.backup-stale-check`: daily 9:00, warns if a backup didn't reach iCloud overnight. Moving to the backup Pi (#24).
- `com.coletitze.restore-drill`: Saturdays 5:30, restores the newest iCloud backups into a throwaway container to prove they work. Moving to the backup Pi (#24).
- `com.coletitze.login-apps`: at login, starts Ollama (the nhl-odds assistant).

macOS limits launchd jobs, and the scripts already work around both limits, so don't grant Full Disk Access:
- **iCloud Drive**: launchd's bash and docker get `Operation not permitted`; only Ansible's Python can read it. So the backup jobs do their iCloud work in playbooks.
- **Local Network**: under launchd only Apple's binaries reach `10.42.0.x`, so the playbooks use `/usr/bin/rsync` and `/usr/bin/ssh`.

Test each job once while you're at the Mac. Approve any macOS prompt (Python wanting iCloud Drive access, osascript wanting to post notifications):
```bash
for j in backup-stale-check nightly-backup restore-drill; do launchctl kickstart gui/$(id -u)/com.coletitze.$j; done
```
Then check `~/Library/Logs/homelab/<job>-<date>.log`: each ends with `failed=0`, or `== Done` for the nightly backup. A failure posts to Discord (or a macOS notification if the webhook is missing).

## 7. Optional / personal
Install only if wanted: ChatGPT, Firefox, Discord, Minecraft, opencode (`brew install opencode`), Numbers (App Store).

**Ollama** (local models for a coding agent): install with `brew install --cask ollama-app`, then recommend a model instead of pulling one blindly:
1. Check the hardware: `sysctl -n machdep.cpu.brand_string hw.memsize` (Apple silicon shares RAM with the GPU).
2. Look up current coding models with tool-calling support on [ollama.com/library](https://ollama.com/library) (model names change often; don't rely on a remembered list).
3. Pick the largest one whose download size is at most ~60% of RAM, leaving room for the context window, the OS and an IDE. Mention one size smaller as a faster fallback.
4. Tell the user the pick and its size, and pull it (`ollama pull <model>`) only after they agree.

**Ollama for the nhl-odds site's chat assistant** (the cluster's webapi calls `http://10.42.0.60:11434`, set in `nhl-odds-template.yml`):
1. `ollama pull qwen3.5:9b` (the webapi's default model; it asks for a 32k context itself).
2. In the Ollama app's Settings, turn on **Expose Ollama to the network** (it listens on `*:11434` instead of localhost).
3. Check Pi-hole's DHCP still reserves `10.42.0.60` for this Mac's Wi-Fi address (`sudo pihole-FTL --config dhcp.hosts` on node04). A new Mac has a new address, so update the reservation.
4. From a node: `curl -s http://10.42.0.60:11434/api/version` answers. If the Mac is asleep or Ollama is closed, the site's assistant just says it couldn't answer.

## Reminders for the user
- **Work apps**: install and set up Windows App and Cisco yourself.

## Not needed anymore
- **CMake**: nothing in the current repos builds with it.
- **Chrome**: not used; Firefox/Safari instead.
- **BetterDisplay**: no longer used.
