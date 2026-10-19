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
brew install gh libomp   # libomp: LightGBM/XGBoost/torch in nhl-odds
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
uv python install 3.14                # newest stable minor (also what the nhl-odds Dockerfile uses)
uv tool update-shell                  # puts ~/.local/bin (uv tools) on PATH; open a new shell after
```
- **.NET 10 SDK** (nhl-odds targets net10.0): `brew install --cask dotnet-sdk`. It runs Microsoft's installer, so it asks for your password **(manual)**.
- Python comes only from uv: don't install python.org or Homebrew Python. Replace `3.14` with the newest stable minor in `uv python list --managed-python`. The `update-mac` skill keeps Pythons, Ansible and the venvs current.

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
uv venv --managed-python --python 3.14 .venv
VIRTUAL_ENV=$PWD/.venv uv pip install -r game_predictor/requirements.txt -r game_predictor/requirements-experimental.txt
```

## 6b. Scheduled jobs (control machine only)
Run on the Mac that stays on as the homelab control machine (one Mac only, or the jobs run twice).

Before installing, check what the jobs need:
- **Vars files**: `ls ~/source/ansible-files/vars` shows `cluster_vars.yml`, `nhl_vars.yml`, `retirement_vars.yml` and `alerting_vars.yml`. They come down with iCloud (section 2), so nothing to restore by hand. If one is missing, iCloud hasn't finished syncing; wait.
- **Vault password** in the login keychain (section 5): `cd ~/source/repos/ansible-setup && ansible-vault view ~/source/ansible-files/vars/cluster_vars.yml >/dev/null && echo OK`.
- **Logins and keys**: `claude` logged in (Start here), `gh auth status` OK, and `~/.ssh` + `~/.kube` restored (section 2). Check `ssh -i ~/.ssh/node01 -o BatchMode=yes pi@10.42.0.20 true` and `kubectl get nodes`.
- **Docker Desktop** set to start at login (Settings → General). The restore drill starts it if it's closed, but it must be installed.

Install the jobs:
```bash
cd ~/source/repos/ansible-setup && ansible-playbook mac-playbooks/scheduled-jobs/scheduled-jobs.yml
```
It installs four launchd LaunchAgents that run as you, with your tools, keys and logins:
- `com.coletitze.nightly-backup`: daily 3:10, runs `mac-playbooks/backup/scripts/Backup.sh` (after the cluster's nhl-odds dumps, the 1:30 Grafana backup and kured's 2:00-2:55 reboots).
- `com.coletitze.backup-stale-check`: daily 9:00, warns if a backup didn't reach iCloud overnight.
- `com.coletitze.restore-drill`: Saturdays 4:00, restores the newest iCloud backups into a throwaway container to prove they work.
- `com.coletitze.weekly-upgrade`: Sundays 10:00, runs Claude Code headless with `scripts/weekly-upgrade-prompt.md` (the weekly jobs check, `/k8s-major-upgrade` and `/nhl-odds-security`, applying changes unattended).

macOS limits launchd jobs, and the scripts already work around both limits, so don't grant Full Disk Access:
- **iCloud Drive**: launchd's bash, docker and Claude's Bash get `Operation not permitted`; only Ansible's Python can read it. So the backup jobs do their iCloud work in playbooks, and the weekly upgrade has Ansible copy `vars/` to a private temp dir (deleted after the run) and points the cluster playbooks at it with `ANSIBLE_FILES_PATH`.
- **Local Network**: under launchd only Apple's binaries reach `10.42.0.x`, so the weekly upgrade tunnels the K3s API over ssh.

Test each job once while you're at the Mac. Approve any macOS prompt (Python wanting iCloud Drive access, Terminal or osascript wanting to post notifications):
```bash
for j in backup-stale-check nightly-backup restore-drill; do launchctl kickstart gui/$(id -u)/com.coletitze.$j; done
```
Then check `~/Library/Logs/homelab/<job>-<date>.log`: each ends with `failed=0`, or `== Done` for the nightly backup. Leave the weekly upgrade to its Sunday run: it changes the cluster. Logs and the weekly summary go to `~/Library/Logs/homelab/`, and a macOS notification fires on failure (and when the weekly run finishes).

## 7. Optional / personal
Install only if wanted: ChatGPT, Firefox, Discord, Minecraft.

**Ollama** (local models for a coding agent): install with `brew install --cask ollama`, then recommend a model instead of pulling one blindly:
1. Check the hardware: `sysctl -n machdep.cpu.brand_string hw.memsize` (Apple silicon shares RAM with the GPU).
2. Look up current coding models with tool-calling support on [ollama.com/library](https://ollama.com/library) (model names change often; don't rely on a remembered list).
3. Pick the largest one whose download size is at most ~60% of RAM, leaving room for the context window, the OS and an IDE. Mention one size smaller as a faster fallback.
4. Tell the user the pick and its size, and pull it (`ollama pull <model>`) only after they agree.

## Reminders for the user
- **Work apps**: install and set up Windows App and Cisco yourself.

## Not needed anymore
- **CMake**: nothing in the current repos builds with it.
- **Chrome**: not used; Firefox/Safari instead.
- **BetterDisplay**: no longer used.
