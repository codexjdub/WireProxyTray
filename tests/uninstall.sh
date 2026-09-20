#!/usr/bin/env bash
# Live removal must not strand a connection when runtime state is unavailable.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
prefix=$temp/live
mkdir -p "$prefix/bin" "$temp/unit"
printf '#!/usr/bin/env bash\nexit 0\n' >"$prefix/bin/wireproxyctl"
chmod +x "$prefix/bin/wireproxyctl"

if env -u XDG_RUNTIME_DIR bash "$root/scripts/uninstall.sh" \
    --prefix "$prefix" --unit-dir "$temp/unit" >"$temp/output" 2>&1; then
    echo 'Live uninstall unexpectedly succeeded without XDG_RUNTIME_DIR.' >&2
    exit 1
fi
grep -q 'XDG_RUNTIME_DIR is unavailable' "$temp/output"
[[ -x $prefix/bin/wireproxyctl ]]
echo 'Uninstall regression passed: missing runtime leaves management files intact.'
