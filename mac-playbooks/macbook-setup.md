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
uv python install 3.14 3.12           # newest stable minor + the one the nhl-odds Dockerfile uses
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

## 6. Repos and Claude skills
Clone into `~/source/repos`: `ansible-setup`, `claude-skills`, `nhl-odds`, `retirement-calculator`, `containers`, and the `ansible-role-*` repos.
Then run the `mac-setup` skill from `claude-skills` to link skills into `~/.claude/skills`.
For nhl-odds, follow its `CLAUDE.md` (`npm install` in `frontend/`, `python -m game_predictor.libomp`), but create the venv with uv on the Dockerfile's Python minor so it picks up patch releases automatically:
```bash
uv venv --managed-python --python 3.12 .venv
VIRTUAL_ENV=$PWD/.venv uv pip install -r game_predictor/requirements.txt -r game_predictor/requirements-experimental.txt
```

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
