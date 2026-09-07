#!/usr/bin/env bash
# Maintainer-only cross-build. ARM64 executables are never run by this script.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:-}
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: scripts/release.sh vMAJOR.MINOR.PATCH' >&2; exit 1; }
go=${GO:-go}
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
extras=()
for item in LICENSE CHANGELOG.md .github .gitignore; do [[ ! -e $root/$item ]] || extras+=("$item"); done
mkdir -p "$root/build/releases/$version"
for target in amd64 arm64; do
    stage=$temp/$target
    mkdir -p "$stage"
    tar -C "$root" \
        -cf - wireproxyctl licenses scripts README.md GUIDE.md Makefile tray tests "${extras[@]}" | tar -xf - -C "$stage"
    (
        cd "$stage"
        export GOOS=linux GOARCH=$target CGO_ENABLED=0
        GO="$go" bash scripts/build-wireproxy.sh
        make tray GO="$go" VERSION="$version"
        printf 'WireProxyTray %s\nTarget: linux/%s\n' "$version" "$target" >RELEASE.txt
        if [[ $target == arm64 ]]; then
            echo 'ARM64: cross-compiled successfully; not runtime-tested on ARM hardware or an emulator.' >>RELEASE.txt
        fi
        bash scripts/package.sh
    )
    cp "$stage/build/releases/wireproxyctl-linux-$target.tar.gz" "$stage/build/releases/wireproxyctl-linux-$target.tar.gz.sha256" "$root/build/releases/$version/"
done
(
    cd "$root/build/releases/$version"
    sha256sum wireproxyctl-linux-amd64.tar.gz wireproxyctl-linux-arm64.tar.gz >SHA256SUMS
)
echo "Release packages: build/releases/$version/"
