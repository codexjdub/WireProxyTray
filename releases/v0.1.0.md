# WireProxyTray v0.1.0

Lightweight Linux tray and CLI for wireproxy. Supply a regular WireGuard config; WireProxyTray adds the local SOCKS5 settings without modifying the original file.

## Downloads

- **AMD64 / x86-64:** `wireproxyctl-linux-amd64.tar.gz`
- **ARM64 / AArch64:** `wireproxyctl-linux-arm64.tar.gz`
- **SHA256SUMS:** checksums for both packages.

Both packages include the Bash CLI, static Go tray, static wireproxy binary, installer, source, and license notices. No Go installation or separate wireproxy download is required.

**ARM64:** Cross-compiled successfully; not runtime-tested on ARM hardware or an emulator. Architecture and package contents were checked only.

## Install

Download the package for your architecture and its `.sha256` file into the same directory. For AMD64:

```sh
sha256sum -c wireproxyctl-linux-amd64.tar.gz.sha256
tar -xzf wireproxyctl-linux-amd64.tar.gz
cd wireproxyctl
bash scripts/install.sh --tray
export PATH="$HOME/.local/bin:$PATH"
wireproxy-tray
```

Use the `arm64` filenames on ARM64. Omit `--tray` for CLI-only installation.

```sh
wireproxyctl connect ~/vpn/work.conf
wireproxyctl check
wireproxyctl disconnect
```

## Requirements and known limits

- Linux, Bash/coreutils, awk, util-linux (`flock`) and iproute2 (`ss`).
- systemd user service for background mode; foreground mode works without it.
- curl for on-demand connection checks.
- Tray requires a StatusNotifier-capable host and a desktop portal FileChooser backend. GNOME may need an AppIndicator extension.
- Custom port entry needs optional Zenity; preset ports work without it.
- One active connection; no login autostart. Quitting the tray leaves the connection running.
- AMD64: CLI, local SOCKS5 handshake, systemd lifecycle and isolated D-Bus tests passed. No real provider configuration was supplied for an end-to-end VPN test.
- wireproxy is pinned to source commit `70dabd8db2cb9e0cf4f3d3b9f528fb8637ad3379`; this is a source snapshot, not a claimed upstream release version.
