Weekly homelab upgrade + nhl-odds security pass. You are running headless on my Mac, started by launchd on Sunday at 10:00 CT, after the Sunday jobs: the weekly load test (12:30 AM CT, cluster CronJob nhl-odds-weekly-load-test), the weekly nhl-odds image rebuilds (GitHub cron 08:00 UTC), the Trivy security scan (security-scan.yml, 10:00 UTC) and the daily dependabot-merge.yml (14:00 UTC). This run is unattended and I set it up on purpose: treat this prompt as my standing "yes" to every change the skills would normally ask me to confirm. Don't stop to ask; no one is watching.

Skills are in ~/.claude/skills/<name>/SKILL.md (source of truth: ~/source/repos/claude-skills/<name>/SKILL.md). Repos are under ~/source/repos (ansible-setup, nhl-odds, retirement-calculator, containers, claude-skills). Use the Mac's kubectl, gh, ansible, docker and ssh keys as the skills describe (helm is not installed on the Mac; the skill runs it on node01 over ssh). Before starting, `git pull --ff-only` each repo you'll touch. Network note: under launchd, macOS only lets Apple's own binaries (ssh, curl) reach the LAN, so kubectl talks to the K3s API through an ssh tunnel on localhost — KUBECONFIG is already set for it; don't use or edit ~/.kube/config. SSH to nodes the way the skills do (`ssh -i ~/.ssh/<node> pi@<ip>`). Any other non-Apple tool that needs a 10.42.0.x address must run on a node over ssh or go through kubectl. If the cluster or GitHub can't be reached (kubectl/ssh/gh fail), don't improvise another route: stop and report exactly what was unreachable.

PART 1 — Check this morning's weekly jobs
- Latest run of every workflow in every app repo (nhl-odds, retirement-calculator, containers), using the k8s-major-upgrade skill's "Scheduled builds and CI" section: the Sunday image builds (nhl-odds 08:00 UTC, containers' Docker Publish 08:00 UTC), security-scan.yml, dependabot-merge.yml, and the rest. Report the conclusion and any failed jobs (`gh run view <id> --log-failed`). Read finished runs only; if a run is still in progress, note it and move on. Don't poll.
- The weekly load test: `kubectl get jobs -n nhl-odds` for the nhl-odds-weekly-load-test job's status, and the ErrorLog rows with Source 'LoadTest' since last Sunday (query the DB the way the nhl-error-triage skill does). Report-only.
- If a build failed for a fixable reason (e.g. a broken dependency, a flaky step), fix it per Part 3's rules; otherwise report it.
- Uptime blips (before Part 2, so its upgrades don't muddy the week). The admin page's uptime chart counts every failed minute of the public blackbox probe; one-minute blips never fire NhlOddsSiteDown (5 min) or the burn alerts, so nothing else looks at them.
  - List the past 7 days' failed minutes: Prometheus `query_range` (step 60) of `probe_success{job="probe/default/nhl-odds-public"} == 0` via `kubectl get --raw "/api/v1/namespaces/default/services/http:cluster-monitoring-kube-pr-prometheus:9090/proxy/api/v1/query_range?..."`. Cross-check the daily totals with the `UptimeDay` table (DB read the way the nhl-error-triage skill does; missing probes count as down there too).
  - Classify each with `probe_http_duration_seconds` (by phase), `probe_http_status_code` and `probe_duration_seconds` at that minute: **no connect** (status 0, connect≈0: the probe never reached Cloudflare, so the home WAN or the edge), **slow** (status 200 but total hit the 5s timeout: name the slow phase), **error** (4xx/5xx; 403 = Cloudflare challenge), or **missing** (no sample: Prometheus or blackbox down).
  - For slow, error and clustered failures, check Loki (`{namespace="nhl-odds"}`, cloudflared, Traefik, node journals) and pod restarts/events within ±5 min, plus kured reboots, the night's jobs and the last 7 days of deploys/upgrades. Name a cause only when the logs show one.
  - Track it: append one line per day to `~/Library/Logs/homelab/uptime-blips.csv` (`day,failed,no_connect,slow,error,missing,uptime_pct,note`; create it with that header if missing, skip days already there) and compare with the previous weeks in it. Say whether it's getting worse.
  - Report-only, unless the cause is clearly a bug in these repos with an obvious fix (e.g. a slow endpoint you can show in the logs); then fix it under Part 3's rules.

PART 2 — Full /k8s-major-upgrade
Read the whole skill and follow it in order (discover, compare, upgrade, verify, update pins/docs), including its Dependabot PRs section. Keep every safety rule, since you're unattended:
- Run its pre-check first. If the cluster is already unhealthy, or a Part 1 job is in a bad state that an upgrade could make worse, upgrade nothing in the cluster; just report.
- One component at a time, in the skill's order and gates (Longhorn and K3s one minor at a time, CNPG operator before a K3s minor that needs it, kube-prometheus-stack CRDs first). Don't force past a gate the skill says isn't met.
- Run the skill's health verification after every upgrade. If one fails, stop all further cluster upgrades, apply the skill's rollback/fix guidance for that component only, and report.
- Don't start a Longhorn or K3s upgrade that can't finish before ~00:45 CT.
- Postgres majors only as the skill allows (CNPG image must exist).

PART 3 — /nhl-odds-security, then fix what it can
Read ~/.claude/skills/nhl-odds-security/SKILL.md and run Steps 1–7 against this morning's scan. Then apply the fixes:
- Actionable app-dependency CVEs (fix version exists) → bump the dependency.
- OS CVEs fixable by a base-image bump → bump the base image (respect the Dependabot ignores for .NET/Node/Postgres majors: report those as "available", don't move them).
- Stale trivy-action / Trivy pins → update both `uses:` lines to the new tag's commit SHA (never a bare tag or the master branch) and TRIVY_VERSION together, as Step 6 says.
- Workflow warnings with a clear fix → fix them, following Step 7's pitfalls.
- Code findings from Step 5 stay report-only, as the skill says — don't edit code for them.
- retirement-calculator and containers have their own security-scan.yml (retirement-calculator's :prod image and magic-mirror:latest, also Sunday 10:00 UTC). Read their latest finished runs (`gh run view <id> --log-failed`) and triage them the same way: bump dependencies or base images where a fix exists, and keep their trivy-action SHA and TRIVY_VERSION in step with nhl-odds'.
Do these on a local branch and run the repo's checks from k8s-major-upgrade's Dependabot section (nhl-odds: `dotnet build`, `dotnet test`, `cd frontend && npm ci && npm run build && npm run a11y`; retirement-calculator: its lint/test/build checks; plus a Docker build of any image whose Dockerfile changed). If everything passes, push to main. If checks fail and the fix isn't obvious, don't push; leave the branch and report.

PART 4 — /update-mac (last, after Parts 1–3 are finished)
Read ~/.claude/skills/update-mac/SKILL.md and run its check, then apply only its "Safe to apply now" group without asking, keeping every rule and verify/rollback step:
- Apply: Homebrew formulae, Homebrew casks for apps that aren't running (skip a cask if its app is running; don't quit apps), VS Code extensions, npm globals, Python patch/minor releases, Ansible and its collections (with the syntax-check + backup dry-run verify and rollback), the nhl-odds venv (move it to the Dockerfile's Python minor if Part 3 or a Dependabot merge changed it; import check, restore the old venv on failure), gh extensions.
- Skip and list for me: macOS updates, App Store, the .NET SDK, anything needing sudo or a password, running GUI apps, new Node/.NET majors, and Ollama model pulls.
- Run `claude update` as the very last command of the whole run.

Always: never force-push, never delete volumes/PVCs, never close PRs without reason. Commit and push version pins and skill updates the way the skills say (ansible-setup to main; update "Last full run"/current-state notes in claude-skills, keeping ~/.claude/skills in sync per that repo's CLAUDE.md). Leave every repo on its default branch with a clean working tree when you finish, except branches you left on purpose and reported.

Finish with one summary. I read it on my phone: Discord shows only the part above `## Details` and attaches the whole file. Keep it short and plain. Leave out anything that passed and didn't change, except as one grouped line.

Use this layout exactly:

**Weekly upgrade YYYY-MM-DD: ✅ all good / ⚠️ needs you / ❌ something broke**

**Changed**
- One bullet per real change: `component old → new`, a CVE fix, a workflow fix, a merged PR. Group small ones (e.g. "12 Homebrew formulae, 3 casks"). Write "Nothing" if there were none.

**Needs you**
- One bullet per thing I have to do or decide: failures, rollbacks, blocked upgrades, branches you left, open PRs, skipped Mac updates. Say what to do in a few words. Write "Nothing" if there's nothing.

**Uptime** NN.NN% (N failed min; trend: better/same/worse)

Each bullet is one line of 100 characters or less, and the whole part above `## Details` stays under about 1200 characters. Use no tables up there.

## Details
Short sections, one line per item. Mention items that passed and didn't change only as one grouped line (e.g. "All other workflows green", "Traefik, Longhorn, CNPG current").
1. Weekly jobs: failed or still-running workflows/jobs and what you did. Uptime blips: failed minutes by kind with times (CT), causes found, trend vs previous weeks, anything fixed.
2. Upgrades: a line per component that moved, failed or was blocked (old → new, health PASS/FAIL, short note). Then Dependabot PRs merged or left open and why.
3. Security: CVEs fixed and how, CVEs not actionable, Trivy pins, warnings fixed or left, code findings (report-only), most severe first.
4. Mac: what was updated, what failed or was rolled back, what's left for me.
