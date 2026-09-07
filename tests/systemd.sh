#!/usr/bin/env bash
# Real user-manager integration. Creates only a uniquely named runtime unit.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
unit=wireproxyctl-test-$$.service
cleanup() {
    systemctl --user stop "$unit" >/dev/null 2>&1 || :
    systemctl --user disable --runtime "$unit" >/dev/null 2>&1 || :
    systemctl --user reset-failed "$unit" >/dev/null 2>&1 || :
    systemctl --user daemon-reload >/dev/null 2>&1 || :
    rm -rf -- "$temp"
}
trap cleanup EXIT
systemctl --user show-environment >/dev/null
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
mkdir -m700 "$temp/runtime"
# systemctl uses this private manager socket rather than the session-bus variable.
ln -s "$XDG_RUNTIME_DIR/systemd" "$temp/runtime/systemd"
# Only the unit name differs from production, allowing safe coexistence with an installed app.
sed "s/^UNIT=wireproxyctl.service$/UNIT=$unit/" "$root/bin/wireproxyctl" >"$temp/cli"
chmod +x "$temp/cli"
cat >"$temp/wireproxy" <<EOF
#!/usr/bin/env bash
if [[ \$1 == -n ]]; then exit 0; fi
if [[ -f $temp/crash ]]; then exit 1; fi
exec sleep 120
EOF
chmod +x "$temp/wireproxy"
cat >"$temp/wg.conf" <<'EOF'
[Interface]
PrivateKey = dummy
[Peer]
PublicKey = dummy
EOF
chmod 600 "$temp/wg.conf"
sed -e "s|@CLI@|$temp/cli|" -e "s|Environment=XDG_RUNTIME_DIR=%t|Environment=XDG_RUNTIME_DIR=$temp/runtime|" \
    -e 's/RestartSec=3/RestartSec=1/' "$root/scripts/wireproxyctl.service.in" >"$temp/$unit"
systemctl --user link --runtime "$temp/$unit" >/dev/null
systemctl --user daemon-reload
export XDG_RUNTIME_DIR=$temp/runtime WIREPROXY_BINARY=$temp/wireproxy
"$temp/cli" connect "$temp/wg.conf" --port 49184
for ((i=0;i<50;i++)); do
    pid=$(systemctl --user show "$unit" --property=MainPID --value)
    if [[ $pid != 0 && $(readlink "/proc/$pid/exe" || :) == */sleep ]]; then break; fi
    sleep 0.05
done
[[ $(readlink "/proc/$pid/exe") == */sleep ]] || exit 1
"$temp/cli" status --json | grep -q '"running"'
# Simulate a crash: service must restart with a new PID.
systemctl --user kill --signal=SIGKILL "$unit"
for ((i=0;i<80;i++)); do
    newpid=$(systemctl --user show "$unit" --property=MainPID --value)
    if [[ $newpid != 0 && $newpid != "$pid" ]]; then break; fi
    sleep 0.05
done
[[ $newpid != 0 && $newpid != "$pid" ]] || exit 1
"$temp/cli" disconnect
[[ $(systemctl --user show "$unit" --property=ActiveState --value) == inactive ]] || exit 1
[[ ! -e $temp/runtime/wireproxyctl/active.conf ]] || exit 1
# Continuous failures must eventually hit the configured start limit.
touch "$temp/crash"
"$temp/cli" connect "$temp/wg.conf" --port 49184 || :
for ((i=0;i<160;i++)); do
    active=$(systemctl --user show "$unit" --property=ActiveState --value)
    [[ $active == failed ]] && break
    sleep 0.05
done
[[ $active == failed ]] || exit 1
"$temp/cli" disconnect
echo 'Real systemd: exec ownership, crash restart, explicit stop and retry limit passed.'
