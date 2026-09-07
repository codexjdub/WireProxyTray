#!/usr/bin/env bash
# Repeat installs must repair read-only notices left by older installers.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
args=(--tray --prefix '/opt/wire proxy' --unit-dir /etc/systemd/user --destdir "$temp/stage")
bash "$root/scripts/install.sh" "${args[@]}" >/dev/null
prefix=$temp/stage/opt/'wire proxy'
shopt -s globstar nullglob
files=("$prefix/share/doc/wireproxyctl/tray"/**/LICENSE "$prefix/libexec/wireproxyctl/licenses"/**/LICENSE)
(( ${#files[@]} >= 4 ))
for file in "${files[@]}"; do
    [[ $(stat -c %a -- "$file") == 644 ]]
    chmod 444 -- "$file"
done
bash "$root/scripts/install.sh" "${args[@]}" >/dev/null
for file in "${files[@]}"; do [[ $(stat -c %a -- "$file") == 644 ]]; done
# A third unmodified install verifies ordinary repeat installation as well.
bash "$root/scripts/install.sh" "${args[@]}" >/dev/null
cmp "$root/licenses/tray/fyne.io_systray@v1.12.2/LICENSE" "$prefix/share/doc/wireproxyctl/tray/fyne.io_systray@v1.12.2/LICENSE"
bash "$root/scripts/uninstall.sh" --prefix '/opt/wire proxy' --unit-dir /etc/systemd/user --destdir "$temp/stage" >/dev/null
[[ ! -e $prefix/bin/wireproxyctl && ! -e $prefix/libexec/wireproxyctl ]]
echo 'Install regression passed: first install, read-only legacy files, repeat install and uninstall.'
