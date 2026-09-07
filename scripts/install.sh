#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
prefix=${HOME}/.local
unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
destdir=
tray=false
# Module-cache license files can be mode 0444. install replaces old read-only
# files and sets an explicit mode, so upgrades and repeat installs are safe.
install_notices() (
    local source=$1 destination=$2 file
    shopt -s globstar nullglob dotglob
    for file in "$source"/**; do
        [[ -f $file ]] || continue
        install -Dm644 -- "$file" "$destination/${file#"$source"/}"
    done
)
while (( $# )); do
    case $1 in
        --prefix|--unit-dir|--destdir)
            (( $# >= 2 )) || { echo "Missing value for $1" >&2; exit 1; }
            case $1 in --prefix) prefix=$2;; --unit-dir) unit_dir=$2;; --destdir) destdir=$2;; esac
            shift 2;;
        --tray) tray=true; shift;;
        --help) echo 'Usage: scripts/install.sh [--tray] [--prefix PATH] [--unit-dir PATH] [--destdir STAGING_ROOT]'; exit 0;;
        *) echo "Unknown option: $1" >&2; exit 1;;
    esac
done
for path in "$prefix" "$unit_dir" "${destdir:-/}"; do
    [[ $path = /* && ! $path =~ [[:cntrl:]] ]] || { echo 'Paths must be absolute and contain no control characters.' >&2; exit 1; }
done
if $tray && [[ ! -x $root/bin/wireproxy-tray ]]; then
    echo 'Build the tray first: make tray' >&2; exit 1
fi
bundle=$root/libexec/wireproxyctl
if [[ ! -x $bundle/wireproxy || ! -f $bundle/SHA256SUMS || ! -f $bundle/LICENSE || ! -f $bundle/BUILD.txt || ! -d $bundle/licenses ]]; then
    echo 'The wireproxy bundle is missing. Use a complete distribution, or run make wireproxy as a maintainer.' >&2; exit 1
fi
(cd "$bundle" && sha256sum --check --status SHA256SUMS) || { echo 'Bundled wireproxy checksum failed.' >&2; exit 1; }
case $(uname -m) in x86_64) architecture=amd64;; aarch64|arm64) architecture=arm64;; *) architecture=$(uname -m);; esac
grep -Fx "Target: linux/$architecture" "$bundle/BUILD.txt" >/dev/null || { echo 'This wireproxy bundle was built for a different architecture.' >&2; exit 1; }
install -Dm755 "$bundle/wireproxy" "$destdir$prefix/libexec/wireproxyctl/wireproxy"
for file in LICENSE BUILD.txt SHA256SUMS; do
    install -m644 "$bundle/$file" "$destdir$prefix/libexec/wireproxyctl/$file"
done
install_notices "$bundle/licenses" "$destdir$prefix/libexec/wireproxyctl/licenses"
install -Dm755 "$root/bin/wireproxyctl" "$destdir$prefix/bin/wireproxyctl"
# systemd ExecStart quoting includes literal dollars and percent specifiers.
cli=$prefix/bin/wireproxyctl
escaped=${cli//\\/\\\\}; escaped=${escaped//\"/\\\"}; escaped=${escaped//\$/\$\$}; escaped=${escaped//%/%%}
mkdir -p -- "$destdir$unit_dir"
while IFS= read -r line; do
    if [[ $line == ExecStart=* ]]; then printf 'ExecStart="%s" _run\n' "$escaped"; else printf '%s\n' "$line"; fi
done <"$root/packaging/wireproxyctl.service.in" >"$destdir$unit_dir/wireproxyctl.service"
chmod 644 "$destdir$unit_dir/wireproxyctl.service"
if $tray; then
    install -Dm755 "$root/bin/wireproxy-tray" "$destdir$prefix/bin/wireproxy-tray"
    mkdir -p "$destdir$prefix/share/doc/wireproxyctl"
    install_notices "$root/licenses/tray" "$destdir$prefix/share/doc/wireproxyctl/tray"
    desktop=$destdir$prefix/share/applications/wireproxy-tray.desktop
    mkdir -p -- "$(dirname -- "$desktop")"
    # Desktop Exec requires extra backslash escaping, distinct from systemd syntax.
    escaped=$prefix/bin/wireproxy-tray
    escaped=${escaped//\\/\\\\\\\\}; escaped=${escaped//\"/\\\\\"}; escaped=${escaped//\$/\\\\\$}; escaped=${escaped//\`/\\\\\`}; escaped=${escaped//%/%%}
    printf '[Desktop Entry]\nType=Application\nName=WireProxy Tray\nComment=Control a WireGuard proxy\nExec="%s"\nIcon=network-vpn\nTerminal=false\nCategories=Network;\n' "$escaped" >"$desktop"
fi
if [[ -z $destdir ]]; then
    if ! systemctl --user daemon-reload; then
        echo 'Files installed. A user systemd session is unavailable; run systemctl --user daemon-reload when available, or use --foreground.' >&2
    fi
fi
printf 'Installed CLI: %s/bin/wireproxyctl\nUser service: %s/wireproxyctl.service\n' "$prefix" "$unit_dir"
printf 'Bundled wireproxy: %s/libexec/wireproxyctl/wireproxy\n' "$prefix"
echo 'No service was started or enabled. No separate wireproxy download is needed.'
if $tray; then echo "Tray: $prefix/bin/wireproxy-tray (optional; not autostarted)"; fi
