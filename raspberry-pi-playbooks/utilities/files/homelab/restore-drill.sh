#!/bin/bash
# Weekly proof that the backup Pi's copies restore, started by homelab-restore-drill.timer on
# Saturdays at 5:00 CT, after the 4:00 pull (backup-node-jobs.yml). Posts the result to Discord.
# - nhl-odds: newest dump -> a throwaway PostgreSQL 18 (prod's major) in a scratch folder, socket
#   only, then sanity checks
# - Grafana: SQLite integrity check on the newest grafana-*.db (dashboards are in git; it holds stars + users)
# The Mac's nightly copy checks the iCloud copies against SHA256SUMS. Leaves nothing behind.
set -uo pipefail
. /usr/local/lib/homelab/common.sh

BACKUPS=/home/pi/backups
SCRATCH=/var/tmp/restore-drill
PGBIN=/usr/lib/postgresql/18/bin
MIN_TABLES=50
# Dumps are taken around 1 AM, so the newest finished job is normally from the day before
MAX_LAG_DAYS=2
LOG="$LOG_DIR/restore-drill-$(date +%Y-%m-%d).log"
failures=()
results=()

as_postgres() { runuser -u postgres -- "$@"; }
cleanup() {
  [ -f "$SCRATCH/data/postmaster.pid" ] && as_postgres "$PGBIN/pg_ctl" -D "$SCRATCH/data" -m immediate stop >/dev/null 2>&1
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

drill_nhl() {
  local dump t0 t1 tables size last_job lag
  dump=$(ls -1 "$BACKUPS"/nhl-odds/nhl-????-??-??.dump 2>/dev/null | sort | tail -1)
  [ -n "$dump" ] || { failures+=("nhl-odds: no backup found"); return; }

  cleanup
  install -d -o postgres -g postgres -m 0700 "$SCRATCH"
  # Throwaway cluster: no fsync, listens only on a socket in the scratch folder
  as_postgres "$PGBIN/initdb" -D "$SCRATCH/data" -U postgres --auth=trust >/dev/null || { failures+=("nhl-odds: initdb failed"); return; }
  as_postgres "$PGBIN/pg_ctl" -D "$SCRATCH/data" -l "$SCRATCH/postgres.log" -w -t 120 \
    -o "-c listen_addresses='' -k $SCRATCH -c fsync=off -c full_page_writes=off -c synchronous_commit=off -c max_wal_size=4GB -c maintenance_work_mem=512MB" \
    start >/dev/null || { failures+=("nhl-odds: postgres didn't start"); tail -5 "$SCRATCH/postgres.log"; return; }

  q() { psql -h "$SCRATCH" -U postgres -d nhl -Atc "$1"; }
  createdb -h "$SCRATCH" -U postgres nhl || { failures+=("nhl-odds: createdb failed"); return; }
  t0=$(date +%s)
  # Runs as root (reads the dump in pi's home); the server only sees the socket connection
  if ! pg_restore -h "$SCRATCH" -U postgres -d nhl -j 4 --no-owner --no-privileges --exit-on-error "$dump" 2>"$SCRATCH/restore.err"; then
    failures+=("nhl-odds: restore failed: $(tail -1 "$SCRATCH/restore.err")")
    cat "$SCRATCH/restore.err"
    return
  fi
  t1=$(date +%s)
  tables=$(q 'select count(*) from pg_stat_user_tables')
  size=$(q "select pg_size_pretty(pg_database_size('nhl'))")
  last_job=$(q "select max(\"FinishedAt\")::date from \"JobStatus\" where \"Status\" = 'completed'")
  results+=("nhl-odds: $(basename "$dump") restored in $(((t1 - t0) / 60))m$(((t1 - t0) % 60))s, $tables tables, $size, newest job ${last_job:-none}")

  [ "${tables:-0}" -ge $MIN_TABLES ] || failures+=("nhl-odds: only ${tables:-0} tables")
  if [ -n "$last_job" ]; then
    lag=$((($(date -d "$(basename "$dump" | cut -c5-14)" +%s) - $(date -d "$last_job" +%s)) / 86400))
    [ $lag -le $MAX_LAG_DAYS ] || failures+=("nhl-odds: newest job $last_job is $lag days before the dump")
  else
    failures+=("nhl-odds: no completed job found")
  fi
}

drill_grafana() {
  local db integrity users stars
  db=$(ls -1 "$BACKUPS"/grafana/grafana-*.db 2>/dev/null | sort | tail -1)
  [ -n "$db" ] || { failures+=("grafana: no backup found"); return; }
  integrity=$(sqlite3 -readonly "$db" 'pragma integrity_check' 2>&1 | head -1)
  users=$(sqlite3 -readonly "$db" 'select count(*) from user' 2>&1)
  stars=$(sqlite3 -readonly "$db" 'select count(*) from star' 2>&1)
  results+=("grafana: $(basename "$db"): integrity=$integrity, users=$users, stars=$stars")
  [ "$integrity" = ok ] || failures+=("grafana: integrity $integrity")
  [[ "$users" =~ ^[1-9][0-9]*$ ]] || failures+=("grafana: no users")
}

{
  echo "== Restore drill $(date '+%F %T')"
  drill_nhl
  cleanup
  drill_grafana
  printf '%s\n' "${results[@]}"
  [ ${#failures[@]} -eq 0 ] || printf 'DRILL FAILED: %s\n' "${failures[@]}"
  echo "== Done $(date '+%F %T')"
} >>"$LOG" 2>&1

status=0
if [ ${#failures[@]} -gt 0 ]; then
  discord_post "❌ Restore drill FAILED (backup Pi)" "$(printf '%s\n' "${failures[@]}")
Log: $(hostname):$LOG" "$LOG"
  status=1
else
  discord_post "✅ Restore drill passed (backup Pi)" "$(printf '%s\n' "${results[@]}")"
fi

find "$LOG_DIR" -name 'restore-drill-*.log' -mtime +90 -delete
exit $status
