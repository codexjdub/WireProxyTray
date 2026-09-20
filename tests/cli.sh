#!/usr/bin/env bash
# Isolated lifecycle tests. No real services, VPN traffic, or user files are changed.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
fg=
cleanup() { if [[ -n $fg ]]; then kill -TERM "$fg" 2>/dev/null || :; wait "$fg" 2>/dev/null || :; fi; rm -rf -- "$temp"; }
trap cleanup EXIT
export XDG_RUNTIME_DIR=$temp/runtime MOCK_ROOT=$temp/mock
mkdir -m700 "$XDG_RUNTIME_DIR" "$MOCK_ROOT" "$temp/tools"
export REAL_TIMEOUT
REAL_TIMEOUT=$(command -v timeout)
export PATH=$temp/tools:$PATH
export WIREPROXY_BINARY=$temp/tools/wireproxy
cli=$root/wireproxyctl
source_file=$temp/'work $profile; # test.conf'
printf '[Interface]\nPrivateKey = test-secret\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = test\n' >"$source_file"
chmod 600 "$source_file"
original=$(sha256sum "$source_file")
cat >"$temp/tools/wireproxy" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -n ]]; then
    cp "$3" "$MOCK_ROOT/validated"
    if [[ -f $MOCK_ROOT/hang-validation ]]; then
        printf '%s\n' "$$" >"$MOCK_ROOT/validation-pid"
        trap '' TERM
        while :; do :; done
    fi
    [[ ! -f $MOCK_ROOT/invalid ]]
    exit $?
fi
printf '%s\n' "$$" >"$MOCK_ROOT/child"
if [[ -f $MOCK_ROOT/exit ]]; then exit 42; fi
exec sleep 120
EOF
cat >"$temp/tools/timeout" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == --kill-after=5 && ${2:-} == 15 ]] || exit 97
shift 2
exec "$REAL_TIMEOUT" --kill-after=0.2 0.2 "$@"
EOF
cat >"$temp/tools/ss" <<'EOF'
#!/usr/bin/env bash
if [[ -f $MOCK_ROOT/occupied ]]; then echo 'LISTEN 0 128 127.0.0.1:1080'; fi
exit 0
EOF
cat >"$temp/tools/systemctl" <<'EOF'
#!/usr/bin/env bash
shift # --user
case $1 in
    show)
        if [[ $* == *LoadState* ]]; then echo loaded
        elif [[ -f $MOCK_ROOT/active ]]; then printf 'ActiveState=active\nSubState=running\n'
        else printf 'ActiveState=inactive\nSubState=dead\n'; fi;;
    start) if [[ -f $MOCK_ROOT/start-fail ]]; then exit 1; fi; touch "$MOCK_ROOT/active";;
    stop) rm -f "$MOCK_ROOT/active";;
    reset-failed|daemon-reload) :;;
    *) exit 1;;
esac
EOF
cat >"$temp/tools/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$MOCK_ROOT/curl-args"
if [[ -f $MOCK_ROOT/check-fail ]]; then exit 7; fi
printf '203.0.113.12'
EOF
chmod +x "$temp/tools/"*
count=0
pass() { count=$((count+1)); printf 'ok %d - %s\n' "$count" "$1"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
reject() { if "$@" >"$temp/output" 2>&1; then fail "unexpected success: $*"; fi; }
await_file() { for ((i=0;i<100;i++)); do [[ -s $1 ]] && return; sleep 0.03; done; fail "timed out: $1"; }

[[ $("$cli" status --json) == '{"status":"disconnected","mode":"","config":"","proxy":""}' ]] || fail status
pass 'empty state is disconnected'
"$cli" connect "$source_file" --port 01081 >"$temp/output"
[[ $(sha256sum "$source_file") == "$original" ]] || fail 'original modified'
[[ $(stat -c %a "$XDG_RUNTIME_DIR/wireproxyctl/active.conf") == 600 ]] || fail permissions
[[ $(stat -c %a "$XDG_RUNTIME_DIR/wireproxyctl") == 700 ]] || fail directory-permissions
grep -F 'BindAddress = 127.0.0.1:1081' "$XDG_RUNTIME_DIR/wireproxyctl/active.conf" >/dev/null
grep -F "WGConfig = \`$source_file\`" "$XDG_RUNTIME_DIR/wireproxyctl/active.conf" >/dev/null
! grep -q test-secret "$XDG_RUNTIME_DIR/wireproxyctl/active.conf" || fail 'copied secret'
pass 'companion preserves special-character paths, original bytes and permissions'
reject "$cli" connect "$source_file"
grep -q 'Disconnect before' "$temp/output"
pass 'second connection rejected'
"$cli" check >"$temp/output"
grep -q '203.0.113.12' "$temp/output"
grep -Fx 'socks5h://127.0.0.1:1081' "$MOCK_ROOT/curl-args" >/dev/null
grep -Fx -- '--noproxy' "$MOCK_ROOT/curl-args" >/dev/null
[[ $(head -1 "$MOCK_ROOT/curl-args") == -q ]] || fail curlrc
pass 'check forces SOCKS DNS and ignores curl configuration'
touch "$MOCK_ROOT/check-fail"
reject "$cli" check
"$cli" status --json | grep -q '"running"'
pass 'failed connectivity check leaves running process alone'
"$cli" disconnect >/dev/null
[[ ! -e $XDG_RUNTIME_DIR/wireproxyctl/active.conf && ! -e $XDG_RUNTIME_DIR/wireproxyctl/state ]] || fail cleanup
"$cli" disconnect >/dev/null
pass 'disconnect is idempotent and cleans runtime config'
touch "$MOCK_ROOT/invalid"
reject "$cli" connect "$source_file"
[[ ! -e $XDG_RUNTIME_DIR/wireproxyctl/active.conf ]] || fail 'committed invalid config'
rm "$MOCK_ROOT/invalid"
pass 'validation failure leaves no active config'
touch "$MOCK_ROOT/hang-validation"
reject "$cli" connect "$source_file"
validation_pid=$(cat "$MOCK_ROOT/validation-pid")
! kill -0 "$validation_pid" 2>/dev/null || fail 'hung validator survived kill escalation'
[[ ! -e $XDG_RUNTIME_DIR/wireproxyctl/active.conf ]] || fail 'committed hung validation config'
rm "$MOCK_ROOT/hang-validation"
pass 'validation timeout escalates to SIGKILL'
touch "$MOCK_ROOT/occupied"
reject "$cli" connect "$source_file"
grep -q occupied "$temp/output"
rm "$MOCK_ROOT/occupied"
pass 'occupied port is rejected without killing its owner'
for p in 0 80 65536 99999999 bad; do reject "$cli" connect "$source_file" --port "$p"; done
pass 'invalid ports are rejected'
touch "$MOCK_ROOT/start-fail"
reject "$cli" connect "$source_file"
[[ ! -e $XDG_RUNTIME_DIR/wireproxyctl/state ]] || fail 'stale state after start failure'
rm "$MOCK_ROOT/start-fail"
pass 'service start failure rolls back state'

"$cli" connect "$source_file" --foreground >"$temp/foreground-log" 2>&1 & fg=$!
await_file "$MOCK_ROOT/child"
child=$(cat "$MOCK_ROOT/child")
"$cli" status --json | grep -q '"mode":"foreground"'
reject "$cli" connect "$source_file" --foreground
"$cli" disconnect >/dev/null
wait "$fg" || [[ $? == 143 ]]
fg=
! kill -0 "$child" 2>/dev/null || fail 'child left running'
[[ ! -e $XDG_RUNTIME_DIR/wireproxyctl/state ]] || fail 'foreground cleanup'
pass 'foreground stop reaps child, excludes duplicate starts and cleans up'

touch "$MOCK_ROOT/exit"
set +e
"$cli" connect "$source_file" --foreground >"$temp/output" 2>&1
code=$?
set -e
[[ $code == 42 && ! -e $XDG_RUNTIME_DIR/wireproxyctl/state ]] || fail 'exit propagation'
pass 'foreground propagates child exit status'

# An occupied session lock must win even if state is stale or absent.
exec 7>"$XDG_RUNTIME_DIR/wireproxyctl/session.lock"
flock -n 7
reject "$cli" connect "$source_file"
grep -q 'already starting or running' "$temp/output"
flock -u 7; exec 7>&-
pass 'session lock prevents orphan/overlap races'

stage=$temp/stage
bash "$root/scripts/install.sh" --prefix '/opt/wire proxy' --unit-dir /etc/systemd/user --destdir "$stage" >/dev/null
grep -Fx 'ExecStart="/opt/wire proxy/bin/wireproxyctl" _run' "$stage/etc/systemd/user/wireproxyctl.service" >/dev/null
[[ -x $stage/opt/'wire proxy'/bin/wireproxyctl ]] || fail install
bash "$root/scripts/uninstall.sh" --prefix '/opt/wire proxy' --unit-dir /etc/systemd/user --destdir "$stage" >/dev/null
[[ ! -e $stage/opt/'wire proxy'/bin/wireproxyctl ]] || fail uninstall
[[ $(sha256sum "$source_file") == "$original" ]] || fail source
pass 'staged install/uninstall preserves source and handles spaces'
echo "Passed $count CLI integration tests."
