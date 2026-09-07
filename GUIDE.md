# Reference guide

[Installation and everyday use](README.md)

## Configuration and desktop integration

Use a regular WireGuard config with literal keys. The source file stays in place
and must remain readable. The default SOCKS5 listener is `127.0.0.1:1080`.

The tray supports StatusNotifier/DBusMenu hosts, not legacy XEmbed-only trays.
A working `xdg-desktop-portal` FileChooser backend supplies the file picker;
notifications use the desktop notification service. No GTK or Qt toolkit is
linked into the tray.

Ports range from 1024 to 65535. Presets are 1080, 1081, 1082, 8080, and 9050;
custom entry uses Zenity. The selection is saved in
`$XDG_CONFIG_HOME/wireproxyctl/tray-port` (normally
`~/.config/wireproxyctl/tray-port`). `wireproxy-tray --port 1081` overrides it for
one launch. A change applies to the next connection.

`status` distinguishes running, reconnecting, stopping, failed, disconnected,
and unknown. `check` makes one HTTPS request to `api.ipify.org` through SOCKS5
with proxy-side DNS, ignoring curlrc and `NO_PROXY`. `logs --follow` follows the
background service journal; foreground mode writes directly to the terminal.
The tray watches file changes and systemd signals, refreshes on menu open,
and registers again if its host restarts. Only one tray instance runs per
session bus.

## Installation paths and overrides

The installer uses `~/.local/bin`, `~/.local/libexec/wireproxyctl`, and
`$XDG_CONFIG_HOME/systemd/user` (normally `~/.config/systemd/user`). Install and
uninstall accept matching `--prefix`, `--unit-dir`, and `--destdir` arguments.
Close the tray before uninstalling if `busctl` is unavailable.

`WIREPROXY_BINARY=/path/to/wireproxy wireproxyctl connect ~/vpn/work.conf`
overrides the bundled binary. PATH is used only if no bundle exists. The selected
absolute path is remembered for the connection. Runtime metadata is read as
plain data, never sourced as shell code. The installer verifies the bundle's
checksum and architecture before installing.

## Configuration and lifecycle


The source file must be a normal WireGuard config with `[Interface]` and `[Peer]` sections. Wireproxy validates its contents before startup. WireGuard `wg-quick` hooks such as `PostUp` are not executed. Standard WireGuard interface/routing management is not performed. Use literal keys in the file: shell environment variables are not transported into the systemd service.

A generated companion looks like this:

```ini
WGConfig = `/absolute/path/to/work.conf`

[Socks5]
BindAddress = 127.0.0.1:1080
```

It lives in `$XDG_RUNTIME_DIR/wireproxyctl/active.conf`, typically `/run/user/1000/wireproxyctl/active.conf`. The app directory is mode 0700 and files are mode 0600. The original key is not copied. Original files stay in place and must remain readable; changes take effect on the next connection. Filenames with spaces, quotes, `#`, `;`, and `$` are supported; control characters, backticks and the literal sequence `%(WGConfig)s` are rejected because of the include parser.

Companion and state files are removed on explicit disconnect or foreground exit. They are retained while a failed background service awaits inspection/disconnect. Lock files remain so concurrent processes cannot accidentally lock different inodes. The user runtime directory is normally cleared at logout or reboot; login lingering affects its lifetime.

Background mode uses `Restart=on-failure`, with a 3-second delay and at most five starts in 120 seconds. Explicit disconnect stops retries. The service execs wireproxy, so there is no resident Bash supervisor. The user service normally ends when the user manager exits; keeping it alive after logout requires separate user-manager configuration.

Concurrent CLI operations are serialized. A session lock prevents foreground/background overlap, including when an orphan still owns it. A detected listener conflict is reported; the tool never kills unrelated port owners. A different process can still take a port between checking and startup; wireproxy then reports its bind failure through its output/journal.

## Resources

CLI commands run and exit. In background CLI mode, wireproxy is the only added persistent process. Optional tray mode adds the Go helper, which sleeps waiting for events while idle. Connectivity checks run only on request. The UI's file picker and notifications are provided by the desktop.

`tests/resources.sh` measures the helper's RSS/PSS and idle CPU ticks on a private D-Bus session. Wireproxy's resource use depends on traffic and configuration; tray measurements are not a whole-desktop memory estimate.


## Development

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


Dependency notices are kept in `licenses/tray.txt` and `licenses/wireproxy.txt`.
The installer puts them beside the installed components. `libexec/` and `dist/`
contain generated artifacts and are ignored by Git. The systemd service template
lives beside the installer in `scripts/`.

Update `CHANGELOG.md` before a release and use its entry for the GitHub release
notes. Check both packages and their checksums before publishing, and state
which architectures and runtime behaviors were tested.

## Validation

Runtime validation platform: Linux x86-64.

## v0.1.0 release verification — 2026-09-07

Both AMD64 and ARM64 archives built successfully with static executables, matching ELF architectures, bundled dependency notices and verified checksums. ARM64 executables were not run on hardware or an emulator. The extracted AMD64 archive passed CLI and installation regression tests, Go unit tests and vet, private D-Bus tray/portal tests, and a real local SOCKS5 handshake using its bundled wireproxy. No real provider tunnel was tested. Generated binaries and per-build metadata are release assets, not committed source files.

## Passed

- 14 Bash CLI integration scenarios: companion generation, unchanged originals, private permissions, special-character paths, duplicate starts, proxy check arguments, failed checks, cleanup, invalid configs and ports, occupied ports, service-start rollback, foreground shutdown and exit codes, session locks, staged installation/removal.
- Go unit tests: CLI JSON parsing, literal command argument handling, local portal URI decoding/rejection.
- Private D-Bus integration: immediate portal response and cancellation; tray registration; live CLI-state updates; re-registration after a tray host restart; graceful exit.
- Real wireproxy: configuration include with special characters, local SOCKS5 protocol handshake, listener shutdown and config cleanup. Public example keys and a localhost endpoint were used.
- Real systemd user manager: wireproxy owns the main process, crash restart, explicit disconnect, and exhaustion of retry limit. A uniquely named runtime test unit was removed afterward.
- Bash syntax checks, Go vet, and staged desktop launcher validation.
- Bundle follow-up: installed CLI automatically discovered the private wireproxy binary and completed a real SOCKS5 handshake without a binary override. Uninstall preserved a separately installed executable. A corrupted bundle was rejected before any installation files were created. All 14 CLI integration scenarios passed again.
- Installer regression: license files copied from Go's module cache were read-only, causing repeat installation to fail. Notices now use explicit mode 0644 installation. Tests passed for first install, replacement of old 0444 files, a third repeat install and uninstall.
- Tray port selector: unit tests cover numeric validation, saved selection and permissions, dialog output and cancellation. Private D-Bus tests click a preset and Custom, verify the connection label changes and the port is saved, using a mock dialog executable. Live custom entry requires the optional Zenity utility.

The tray was built with Go 1.27.1, cgo disabled, and stripped symbols. `file` confirms a statically linked Linux x86-64 executable. Module dependencies are pinned in `go.mod` and `go.sum`.

The wireproxy bundle is built from windtf/wireproxy commit `70dabd8db2cb9e0cf4f3d3b9f528fb8637ad3379`, the same source used by the initial integration tests. The bundle includes its build provenance, SHA-256 checksum, upstream license and dependency license notices. It installs into a private application directory, preserving separately installed wireproxy executables.

## Idle tray measurement

Reference measurement of the initial tray build, before the port-selector addition, with `dbus-run-session -- bash tests/resources.sh`, no active VPN and no real desktop tray host. After a one-second warmup:

| Metric | Result |
|---|---:|
| Resident memory (RSS) | 14,116 KiB (13.8 MiB) |
| Proportional memory (PSS) | 14,104 KiB |
| CPU time over five seconds | 0 observed ticks at 100 ticks/second |
| Child processes while idle | 0 |
| Executable size | 5,243,040 bytes (5.0 MiB) |

This short sample is not a guarantee of zero CPU usage. Menu interaction, status changes and connection checks cause work. Desktop portal/host memory and wireproxy's traffic-dependent resource usage are not included.

## Remaining limits

- No real provider config was supplied, so VPN handshake, internet traffic and exit IP through an actual tunnel are unverified.
- Tray and portal protocol behavior was tested against mock services on a private bus, not every desktop/bar or a visible native file-picker dialog.
- ShellCheck was not installed; Bash syntax and integration checks passed, but ShellCheck was not run.
- Installation does not start the service or enable autostart.
