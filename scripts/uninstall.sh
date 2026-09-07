#!/usr/bin/env bash
set -euo pipefail
prefix=${HOME}/.local
unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
destdir=
while (( $# )); do
    case $1 in
        --prefix|--unit-dir|--destdir)
            (( $# >= 2 )) || exit 1
            case $1 in --prefix) prefix=$2;; --unit-dir) unit_dir=$2;; --destdir) destdir=$2;; esac
            shift 2;;
        --help) echo 'Usage: scripts/uninstall.sh [--prefix PATH] [--unit-dir PATH] [--destdir STAGING_ROOT]'; exit 0;;
        *) echo "Unknown option: $1" >&2; exit 1;;
    esac
done
for path in "$prefix" "$unit_dir" "${destdir:-/}"; do
    [[ $path = /* && ! $path =~ [[:cntrl:]] ]] || { echo 'Paths must be absolute and contain no control characters.' >&2; exit 1; }
done
if [[ -z $destdir ]]; then
    # Refuse to remove an executable while its managed connection cannot be stopped.
    if [[ -x $prefix/bin/wireproxyctl && -n ${XDG_RUNTIME_DIR:-} ]]; then
        "$prefix/bin/wireproxyctl" disconnect
    fi
    if command -v busctl >/dev/null; then
        owner=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s io.github.wireproxyctl.Tray 2>/dev/null || :)
        if [[ $owner =~ ^u\ ([0-9]+)$ ]]; then
            pid=${BASH_REMATCH[1]}
            if [[ $(readlink -f "/proc/$pid/exe" 2>/dev/null || :) == "$prefix/bin/wireproxy-tray" ]]; then kill -TERM "$pid"; fi
        fi
    fi
fi
rm -f -- "$destdir$prefix/bin/wireproxyctl" "$destdir$prefix/bin/wireproxy-tray" \
    "$destdir$prefix/share/applications/wireproxy-tray.desktop" "$destdir$unit_dir/wireproxyctl.service"
rm -rf -- "$destdir$prefix/libexec/wireproxyctl"
rm -rf -- "$destdir$prefix/share/doc/wireproxyctl"
if [[ -z $destdir ]]; then systemctl --user daemon-reload || :; fi
echo 'Removed wireproxyctl, its bundled wireproxy, and optional tray. Separately installed wireproxy binaries and original WireGuard configs were preserved.'
