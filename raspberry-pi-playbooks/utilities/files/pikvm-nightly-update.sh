#!/bin/bash
# Nightly PiKVM OS update (run by pikvm-nightly-update.timer).
# / is read-only and /var/log is tmpfs, so the log goes to KVMD's persistent storage, which
# kvmd-pstrun mounts read-write while its command runs. Read it at /var/lib/kvmd/pst/data/pikvm-update.log.
# pikvm-update --no-reboot exits 0 when already up to date and 100 when it updated and needs a reboot.
# Any other exit is a failure: pikvm-update leaves / read-write and says not to reboot (the KVMD
# config may be broken), so only exit 100 reboots.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
tmp=$(mktemp)
echo "=== $(date '+%F %T %Z') ===" > "$tmp"
pikvm-update --no-reboot >> "$tmp" 2>&1
rc=$?
case $rc in
    0) echo "Up to date, no reboot" >> "$tmp" ;;
    100) echo "Updated, rebooting" >> "$tmp" ;;
    *) echo "FAILED: pikvm-update exit $rc, not rebooting (/ left read-write)" >> "$tmp" ;;
esac
# Append, keeping the last 2000 lines
kvmd-pstrun -- sh -c 'f=$KVMD_PST_DATA/data/pikvm-update.log; cat "$1" >> "$f" && tail -n 2000 "$f" > "$f.new" && mv "$f.new" "$f"' sh "$tmp"
rm -f "$tmp"
[ $rc -eq 100 ] && reboot
exit $rc
