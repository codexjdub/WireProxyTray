#!/usr/bin/env bash
# Verify offline installation and automatic discovery of the bundled wireproxy.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
stage=$temp/stage
prefix=/opt/wireproxyctl
bash "$root/scripts/install.sh" --tray --prefix "$prefix" --unit-dir /etc/systemd/user --destdir "$stage"
[[ -x $stage$prefix/libexec/wireproxyctl/wireproxy ]]
[[ -s $stage$prefix/libexec/wireproxyctl/LICENSE ]]
# An independently installed wireproxy is deliberately unusable; bundle must take precedence.
printf '#!/bin/sh\nexit 99\n' >"$stage$prefix/bin/wireproxy"
chmod +x "$stage$prefix/bin/wireproxy"
env -u WIREPROXY_BINARY PATH="$stage$prefix/bin:$PATH" CLI_UNDER_TEST="$stage$prefix/bin/wireproxyctl" \
    bash "$root/tests/real-wireproxy.sh"
bash "$root/scripts/uninstall.sh" --prefix "$prefix" --unit-dir /etc/systemd/user --destdir "$stage"
[[ -x $stage$prefix/bin/wireproxy && ! -e $stage$prefix/libexec/wireproxyctl ]]
echo 'Bundled binary discovered automatically; uninstall preserved independent binary.'

# A damaged bundle must fail before creating installation files.
mkdir -p "$temp/broken/scripts" "$temp/broken/libexec/wireproxyctl" "$temp/broken/licenses/wireproxy/dependencies"
cp "$root/scripts/install.sh" "$temp/broken/scripts/"
bad=$temp/broken/libexec/wireproxyctl
printf '#!/bin/sh\nexit 0\n' >"$bad/wireproxy"
chmod +x "$bad/wireproxy"
touch "$temp/broken/licenses/wireproxy/LICENSE" "$bad/BUILD.txt"
printf '%064d  wireproxy\n' 0 >"$bad/SHA256SUMS"
if bash "$temp/broken/scripts/install.sh" --prefix /opt/test --unit-dir /etc/systemd/user --destdir "$temp/rejected" >"$temp/error" 2>&1; then
    echo 'Installer accepted a corrupted bundle' >&2; exit 1
fi
grep -q 'checksum failed' "$temp/error"
[[ ! -e $temp/rejected ]]
echo 'Corrupted binary rejected before installation.'
