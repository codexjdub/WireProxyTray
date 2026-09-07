#!/usr/bin/env bash
# Run under dbus-run-session to measure the idle tray without modifying a desktop.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
pid=
cleanup() { if [[ -n $pid ]]; then kill -TERM "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; fi; rm -rf -- "$temp"; }
trap cleanup EXIT
export XDG_RUNTIME_DIR=$temp
"$root/build/wireproxy-tray" --cli "$root/wireproxyctl" >"$temp/tray.log" 2>&1 & pid=$!
sleep 1
kill -0 "$pid"
ticks_before=$(awk '{print $14+$15}' "/proc/$pid/stat")
sleep 5
ticks_after=$(awk '{print $14+$15}' "/proc/$pid/stat")
printf 'Idle tray memory (KiB):\n'
awk '/^(Rss|Pss):/ {print}' "/proc/$pid/smaps_rollup"
printf 'CPU ticks over 5 seconds: %d (clock ticks/second: %s)\n' "$((ticks_after-ticks_before))" "$(getconf CLK_TCK)"
printf 'Tray binary bytes: %s\n' "$(stat -c %s "$root/build/wireproxy-tray")"
printf 'Child processes: %s\n' "$(pgrep -P "$pid" | wc -l)"
