#!/bin/bash
# Weekly Lighthouse report on the live nhl-odds site, started by homelab-weekly-lighthouse.timer
# (Sat 4:30 CT, backup-node-jobs.yml); the weekly upgrade starts when it ends and reads it. Runs here, not
# in GitHub Actions: Cloudflare answers GitHub's runners with 403s.
# As pi: updates a sparse clone of nhl-odds' frontend, then runs its `npm run lighthouse`
# (frontend/lighthouse/run.mjs) with LIGHTHOUSE_URL set, inside the Playwright image that
# matches its lockfile, on pi's rootless Docker. Report only: scores never fail the job, and
# Discord hears only when the run itself fails.
# Output: ~pi/homelab/lighthouse/<date>/ (summary.md + one HTML report per page; 8 kept).
# Performance is scored on a Pi 4 CPU, so it reads lower than on CI runners: compare week to week.
set -uo pipefail
. /usr/local/lib/homelab/common.sh

SITE=https://nhl.half-built.com
PI_HOME=/home/pi
WORK=$PI_HOME/homelab/lighthouse
REPO=$WORK/nhl-odds
STAMP=$(date +%Y-%m-%d)
OUT=$WORK/$STAMP
LOG="$LOG_DIR/weekly-lighthouse-$STAMP.log"

as_pi() {
  runuser -u pi -- env HOME=$PI_HOME XDG_RUNTIME_DIR=/run/user/1000 \
    DOCKER_HOST=unix:///run/user/1000/docker.sock "$@"
}

run() {
  set -e
  as_pi mkdir -p "$WORK"
  if [ -d "$REPO/.git" ]; then
    as_pi git -C "$REPO" fetch -q --depth 1 origin main
    as_pi git -C "$REPO" reset -q --hard origin/main
  else
    as_pi git clone -q --depth 1 --filter=blob:none --sparse \
      https://github.com/cole-titze/nhl-odds.git "$REPO"
    as_pi git -C "$REPO" sparse-checkout set frontend
  fi
  echo "nhl-odds $(as_pi git -C "$REPO" rev-parse --short HEAD)"
  version=$(jq -r '.packages["node_modules/playwright"].version' "$REPO/frontend/package-lock.json")
  as_pi rm -rf "$OUT"
  as_pi mkdir -p "$OUT" "$WORK/npm-cache"
  # The summary run.mjs writes for a GitHub job summary goes to $OUT instead
  as_pi docker run --rm --ipc=host \
    -v "$REPO/frontend":/w -v "$WORK/npm-cache":/root/.npm -v "$OUT":/out -w /w \
    -e LIGHTHOUSE_URL=$SITE -e LIGHTHOUSE_RUNS=3 -e GITHUB_STEP_SUMMARY=/out/summary.md \
    "mcr.microsoft.com/playwright:v$version-noble" \
    bash -c 'npm ci --no-audit --no-fund --ignore-scripts && npm run lighthouse'
  as_pi cp "$REPO"/frontend/lighthouse/reports/*.html "$OUT/"
  set +e
}

echo "== Weekly Lighthouse $(date '+%F %T')" >>"$LOG"
(run) >>"$LOG" 2>&1
status=$?
echo "== exit $status $(date '+%F %T')" >>"$LOG"

if [ $status -ne 0 ]; then
  discord_post "❌ Weekly Lighthouse FAILED (backup Pi)" "$(tail -5 "$LOG")
Log: $(hostname):$LOG"
fi

# Keep the last 8 weeks of reports, and only this week's Playwright image (pi's other images,
# such as the nhl-odds test copy, are left alone)
find "$WORK" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??' | sort | head -n -8 | xargs -r rm -rf
version=$(jq -r '.packages["node_modules/playwright"].version' "$REPO/frontend/package-lock.json" 2>/dev/null)
as_pi sh -c 'docker images mcr.microsoft.com/playwright --format "{{.Repository}}:{{.Tag}}" |
  grep -vx "$1" | xargs -r docker rmi' sh "mcr.microsoft.com/playwright:v$version-noble" >/dev/null 2>&1
find "$LOG_DIR" -name 'weekly-lighthouse-*.log' -mtime +90 -delete
exit $status
