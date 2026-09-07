#!/usr/bin/env bash
# Optional: WIREPROXY_BINARY=/path/to/wireproxy bash tests/real-wireproxy.sh
# Uses public example keys and a localhost endpoint, never a real VPN account.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cli=${CLI_UNDER_TEST:-$root/bin/wireproxyctl}
temp=$(mktemp -d)
fg=
cleanup() {
    if [[ -n $fg ]]; then "$cli" disconnect >/dev/null 2>&1 || :; wait "$fg" 2>/dev/null || :; fi
    rm -rf -- "$temp"
}
trap cleanup EXIT
export XDG_RUNTIME_DIR=$temp/runtime
mkdir -m700 "$XDG_RUNTIME_DIR"
config=$temp/'wg # semicolon; $dollar.conf'
cat >"$config" <<'EOF'
[Interface]
PrivateKey = LAr1aNSNF9d0MjwUgAVC4020T0N/E5NUtqVv5EnsSz0=
Address = 10.0.0.2/32
[Peer]
PublicKey = QP+A67Z2UBrMgvNIdHv8gPel5URWNLS4B3ZQ2hQIZlg=
Endpoint = 127.0.0.1:9
AllowedIPs = 0.0.0.0/0
EOF
chmod 600 "$config"
port=${TEST_PROXY_PORT:-49183}
"$cli" connect "$config" --port "$port" --foreground >"$temp/log" 2>&1 & fg=$!
for ((i=0;i<100;i++)); do
    if ss -H -ltn "sport = :$port" | grep -q LISTEN; then break; fi
    if ! kill -0 "$fg" 2>/dev/null; then cat "$temp/log"; exit 1; fi
    sleep 0.05
done
"$cli" status --json | grep -q '"running"'
exec 6<>"/dev/tcp/127.0.0.1/$port"
printf '\x05\x01\x00' >&6
response=$(timeout 2 dd bs=1 count=2 <&6 2>/dev/null | od -An -tx1 | tr -d ' \n')
exec 6>&-
[[ $response == 0500 ]] || { echo "Unexpected SOCKS greeting: $response"; exit 1; }
"$cli" disconnect
wait "$fg" || [[ $? == 143 ]]
fg=
[[ ! -e $XDG_RUNTIME_DIR/wireproxyctl/active.conf ]] || exit 1
[[ -z $(ss -H -ltn "sport = :$port") ]] || exit 1
echo 'Real wireproxy: special-character include path, SOCKS5 handshake and cleanup passed.'
