#!/usr/bin/env bash
# Maintainer build step. End users install the resulting bundle without Go/network access.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
commit=70dabd8db2cb9e0cf4f3d3b9f528fb8637ad3379
repository=https://github.com/windtf/wireproxy.git
go=${GO:-go}
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir -p "$temp/source" "$temp/bundle/licenses"
if [[ -n ${WIREPROXY_SOURCE:-} ]]; then
    # Export the exact committed tree, ignoring any local modifications.
    git -C "$WIREPROXY_SOURCE" archive "$commit" | tar -x -C "$temp/source"
else
    git -C "$temp/source" init -q
    git -C "$temp/source" fetch -q --depth=1 "$repository" "$commit"
    git -C "$temp/source" checkout -q --detach FETCH_HEAD
    [[ $(git -C "$temp/source" rev-parse HEAD) == "$commit" ]]
fi
(
    cd "$temp/source"
    export CGO_ENABLED=0 GOOS=linux
    "$go" build -mod=readonly -buildvcs=false -trimpath \
        -ldflags "-s -w -X main.version=wireproxyctl-$commit" -o "$temp/bundle/wireproxy" ./cmd/wireproxy
    "$go" list -mod=readonly -m -f '{{.Path}} {{.Dir}}' all >"$temp/modules"
    printf 'Repository: %s\nCommit: %s\nTarget: linux/%s\nToolchain: %s\n' \
        "$repository" "$commit" "$("$go" env GOARCH)" "$("$go" version)" >"$temp/bundle/BUILD.txt"
    "$go" version -m "$temp/bundle/wireproxy" | sed "1s|^.*: go|wireproxy: go|" >>"$temp/bundle/BUILD.txt"
)
install -m644 "$temp/source/LICENSE" "$temp/bundle/LICENSE"
while read -r module directory; do
    [[ -n $directory ]] || continue
    name=${module//\//_}
    for file in "$directory"/LICENSE* "$directory"/COPYING* "$directory"/NOTICE*; do
        [[ -f $file ]] || continue
        mkdir -p "$temp/bundle/licenses/$name"
        install -m644 "$file" "$temp/bundle/licenses/$name/"
    done
done <"$temp/modules"
install -m644 "$("$go" env GOROOT)/LICENSE" "$temp/bundle/licenses/Go-LICENSE"
(
    cd "$temp/bundle"
    sha256sum wireproxy >SHA256SUMS
)
mkdir -p "$root/libexec/wireproxyctl" "$root/licenses/wireproxy/dependencies"
install -m755 "$temp/bundle/wireproxy" "$root/libexec/wireproxyctl/wireproxy"
install -m644 "$temp/bundle/BUILD.txt" "$temp/bundle/SHA256SUMS" "$root/libexec/wireproxyctl/"
install -m644 "$temp/bundle/LICENSE" "$root/licenses/wireproxy/LICENSE"
cp -R "$temp/bundle/licenses/." "$root/licenses/wireproxy/dependencies/"
echo "Bundled wireproxy at commit $commit in libexec/wireproxyctl/"
