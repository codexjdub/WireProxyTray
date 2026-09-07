# Validation record

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
