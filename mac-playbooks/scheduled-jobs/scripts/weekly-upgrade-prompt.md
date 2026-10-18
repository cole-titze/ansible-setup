Weekly homelab upgrade + nhl-odds security pass. You are running headless on my Mac, started by launchd on Sunday at 10:00 CT, after the Sunday jobs: the weekly load test (12:30 AM CT, cluster CronJob nhl-odds-weekly-load-test), the weekly nhl-odds image rebuilds (GitHub cron 08:00 UTC), the Trivy security scan (security-scan.yml, 10:00 UTC) and the daily dependabot-merge.yml (14:00 UTC). This run is unattended and I set it up on purpose: treat this prompt as my standing "yes" to every change the skills would normally ask me to confirm. Don't stop to ask; no one is watching.

Skills are in ~/.claude/skills/<name>/SKILL.md (source of truth: ~/source/repos/claude-skills/<name>/SKILL.md). Repos are under ~/source/repos (ansible-setup, nhl-odds, retirement-calculator, containers, claude-skills). Use the Mac's kubectl, gh, ansible, docker and ssh keys as the skills describe (helm is not installed on the Mac; the skill runs it on node01 over ssh). Before starting, `git pull --ff-only` each repo you'll touch. Network note: under launchd, macOS only lets Apple's own binaries (ssh, curl) reach the LAN, so kubectl talks to the K3s API through an ssh tunnel on localhost — KUBECONFIG is already set for it; don't use or edit ~/.kube/config. SSH to nodes the way the skills do (`ssh -i ~/.ssh/<node> pi@<ip>`). Any other non-Apple tool that needs a 10.42.0.x address must run on a node over ssh or go through kubectl. If the cluster or GitHub can't be reached (kubectl/ssh/gh fail), don't improvise another route: stop and report exactly what was unreachable.

PART 1 — Check this morning's weekly jobs
- Latest run of every workflow in every app repo (nhl-odds, retirement-calculator, containers), using the k8s-major-upgrade skill's "Scheduled builds and CI" section: the Sunday image builds (nhl-odds 08:00 UTC, containers' Docker Publish 08:00 UTC), security-scan.yml, dependabot-merge.yml, and the rest. Report the conclusion and any failed jobs (`gh run view <id> --log-failed`). Read finished runs only; if a run is still in progress, note it and move on. Don't poll.
- The weekly load test: `kubectl get jobs -n nhl-odds` for the nhl-odds-weekly-load-test job's status, and the ErrorLog rows with Source 'LoadTest' since last Sunday (query the DB the way the nhl-error-triage skill does). Report-only.
- If a build failed for a fixable reason (e.g. a broken dependency, a flaky step), fix it per Part 3's rules; otherwise report it.

PART 2 — Full /k8s-major-upgrade
Read the whole skill and follow it in order (discover, compare, upgrade, verify, update pins/docs), including its Dependabot PRs section. Keep every safety rule, since you're unattended:
- Run its pre-check first. If the cluster is already unhealthy, or a Part 1 job is in a bad state that an upgrade could make worse, upgrade nothing in the cluster; just report.
- One component at a time, in the skill's order and gates (Longhorn and K3s one minor at a time, CNPG operator before a K3s minor that needs it, kube-prometheus-stack CRDs first, Portainer after Longhorn). Don't force past a gate the skill says isn't met.
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
Do these on a local branch and run the repo's checks from k8s-major-upgrade's Dependabot section (nhl-odds: `dotnet build`, `dotnet test`, `cd frontend && npm ci && npm run build && npm run a11y`; plus a Docker build of any image whose Dockerfile changed). If everything passes, push to main. If checks fail and the fix isn't obvious, don't push; leave the branch and report.

Always: never force-push, never delete volumes/PVCs, never close PRs without reason. Commit and push version pins and skill updates the way the skills say (ansible-setup to main; update "Last full run"/current-state notes in claude-skills, keeping ~/.claude/skills in sync per that repo's CLAUDE.md). Leave every repo on its default branch with a clean working tree when you finish, except branches you left on purpose and reported.

Finish with one summary:
1. Weekly jobs: each workflow/job, result, and what you did about failures.
2. Upgrades table: component, old → new (or current/skipped/blocked), health PASS/FAIL, one-line note; Dependabot PRs merged or left open and why.
3. Security: CVEs fixed (and how), CVEs not actionable, Trivy pins, warnings fixed, warnings left, and code findings (report-only), most severe first.
