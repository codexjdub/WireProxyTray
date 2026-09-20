# Changelog

## v0.1.1 — 2026-09-20

- Bound configuration validation even when a custom wireproxy binary ignores
  `SIGTERM`.
- Refuse live uninstallation when the user runtime directory is unavailable,
  preserving the controller needed to stop an active connection.

## v0.1.0 — 2026-09-07

Initial WireProxyTray release:

- Editable Bash CLI with background systemd and foreground operation.
- Ordinary WireGuard configurations with private generated proxy settings.
- Bundled, pinned wireproxy executable with checksum and license notices.
- Optional Go StatusNotifier tray with desktop file selection.
- Preset and custom proxy ports, with saved tray selection.
- On-demand proxy checks and exit IP reporting.
- Connection locking, bounded background restarts, and clean disconnect.
- User-local installation and removal, without login autostart.
- AMD64 and ARM64 release packages. ARM64 is cross-compiled and not runtime-tested.
