#!/usr/bin/env bash
# Package prebuilt binaries together with their source, installer and license notices.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
[[ -x build/wireproxy-tray && -x build/wireproxy ]] || { echo 'Run make wireproxy tray first.' >&2; exit 1; }
(cd build && sha256sum --check --status SHA256SUMS)
target=$(sed -n 's|^Target: linux/||p' build/BUILD.txt)
[[ $target =~ ^[a-z0-9]+$ ]] || exit 1
case $target in amd64) machine='Advanced Micro Devices X86-64';; arm64) machine=AArch64;; *) echo 'Unsupported release architecture' >&2; exit 1;; esac
for executable in build/wireproxy-tray build/wireproxy; do
    actual=$(readelf -h "$executable" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
    [[ $actual == "$machine" ]] || { echo "Architecture mismatch: $executable is $actual, expected $machine" >&2; exit 1; }
done
mkdir -p build/releases
archive=wireproxyctl-linux-$target.tar.gz
extras=()
for item in CHANGELOG.md RELEASE.txt .github .gitignore; do [[ ! -e $item ]] || extras+=("$item"); done
# Do not publish local usernames, UID/GID, or source-file timestamps in archives.
# A fixed default also makes repeated packaging reproducible.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@${SOURCE_DATE_EPOCH:-0}" \
    -cf - --transform='s|^|wireproxyctl/|' \
    wireproxyctl build/wireproxy-tray build/wireproxy build/BUILD.txt build/SHA256SUMS LICENSE scripts README.md GUIDE.md Makefile tray tests "${extras[@]}" \
    | gzip -n >"build/releases/$archive"
(cd build/releases && sha256sum "$archive" >"$archive.sha256")
echo "Created build/releases/$archive"
