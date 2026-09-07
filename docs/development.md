# Development

[Back to README](../README.md)

Maintainers can rebuild the bundle with `make wireproxy` (Git and Go 1.26+ are required by the pinned wireproxy source), build the tray with `make tray` (Go 1.23+), and create a complete Linux archive with `make package` (requires binutils' `readelf`). `bash scripts/release.sh v0.1.0` builds separate AMD64 and ARM64 packages under `dist/v0.1.0/`, without executing ARM64 binaries. Both binaries disable cgo. `scripts/build-wireproxy.sh` fetches the exact pinned commit and includes upstream and dependency license notices; ordinary installation is offline and performs no build.

```sh
make test
make check
dbus-run-session -- go test -buildvcs=false -tags=integration ./internal/portal ./internal/tray
bash tests/real-wireproxy.sh
bash tests/systemd.sh
bash tests/bundle.sh
dbus-run-session -- bash tests/resources.sh
```

Build the tray before running its D-Bus integration tests. CLI tests use isolated fake tools; the real-wireproxy test uses public example keys, a localhost endpoint, and a real SOCKS5 handshake. It does not establish a VPN tunnel. The systemd test creates and removes a uniquely named runtime user unit, without touching an installed connection. Portal/tray tests use an isolated session bus and mock desktop services. Actual VPN traffic still needs testing with a real provider configuration.

## Repository layout

- `bin/`: Bash CLI; the compiled tray is ignored by Git.
- `cmd/` and `internal/`: Go tray source and tests.
- `scripts/`: build, install, uninstall, and release scripts.
- `tests/`: shell integration tests.
- `packaging/`: systemd service template.
- `licenses/`: dependency notices grouped by tray and wireproxy.
- `docs/`: usage, development, and [validation records](validation.md).
- `releases/`: versioned release notes.
- `libexec/` and `dist/`: generated binaries and packages, ignored by Git.

The installer copies notices from `licenses/` into their installed locations.
Source checkouts contain no prebuilt executables. Release packages include both
executables and the source needed to rebuild them.

For a new release, add `releases/vMAJOR.MINOR.PATCH.md`, update the changelog,
and build with `bash scripts/release.sh vMAJOR.MINOR.PATCH`. Check both packages
and their checksums before publishing. Clearly state which architectures and
runtime behaviors were tested.
