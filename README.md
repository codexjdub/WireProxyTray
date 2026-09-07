# WireProxyTray

A lightweight Linux tray and CLI for [wireproxy](https://github.com/windtf/wireproxy). Point it at a regular WireGuard config; it adds a local SOCKS5 proxy without changing your original file. Use the editable Bash CLI alone or add the optional Go tray.

Inspired by [WireProxyMenu](https://github.com/codexjdub/WireProxyMenu); this is an independent implementation.

## Install

Download the archive for your architecture and its matching `.sha256` file from **[GitHub Releases](https://github.com/codexjdub/WireProxyTray/releases)**. Choose the named package, rather than GitHub's source-only downloads.

| Architecture | Package | Testing |
|---|---|---|
| AMD64 / x86-64 | `wireproxyctl-linux-amd64.tar.gz` | Local CLI, SOCKS5, systemd and D-Bus checks passed |
| ARM64 / AArch64 | `wireproxyctl-linux-arm64.tar.gz` | Cross-compiled; **not runtime-tested** |

AMD64 example (use the ARM64 filenames on ARM64):

```sh
sha256sum -c wireproxyctl-linux-amd64.tar.gz.sha256
tar -xzf wireproxyctl-linux-amd64.tar.gz
cd wireproxyctl
bash scripts/install.sh --tray
export PATH="$HOME/.local/bin:$PATH"
wireproxy-tray
```

Omit `--tray` for CLI-only installation. Both packages include wireproxy and the tray binary; no Go installation or separate wireproxy download is needed. Installation is per-user, needs no root access, and does not enable autostart.

Requirements:

- Linux, Bash 4.4+, GNU coreutils, awk, util-linux (`flock`), and iproute2 (`ss`).
- systemd user services for background connections; foreground mode works without systemd.
- curl for the optional connection check.
- For the tray: a StatusNotifier-capable desktop/bar and a desktop portal FileChooser backend. GNOME may need a tray extension. Custom port entry uses optional Zenity.

## Tray

Choose **Connect** and select your WireGuard config. Use **Proxy port** to pick a preset or enter a custom port. Port changes apply to the next connection.

The menu provides **Disconnect**, **Check connection**, and status information. **Quit tray leaves the connection running.** The tray uses standard desktop interfaces and is not tied to a distribution or bar.

## CLI

```sh
wireproxyctl connect ~/vpn/work.conf
wireproxyctl connect ~/vpn/work.conf --port 1081
wireproxyctl status
wireproxyctl check
wireproxyctl logs
wireproxyctl disconnect
```

For foreground operation without systemd:

```sh
wireproxyctl connect ~/vpn/work.conf --foreground
```

Ctrl+C stops the foreground connection. Only one connection can run at a time.

## Using the proxy

Configure individual apps to use **SOCKS5 at `127.0.0.1:1080`** (or your selected port), with proxy-side DNS. WireProxyTray does not change system routes or system-wide proxy settings.

“Running” means the process is running. Use **Check connection** or `wireproxyctl check` to request an exit-IP check through the proxy. No periodic network checks run; the tray waits for events while idle.

Real VPN traffic has not yet been verified with a provider configuration. See the [validation record](GUIDE.md#validation) for tested behavior and limitations.

## Uninstall

From the extracted package:

```sh
bash scripts/uninstall.sh
```

Your original WireGuard configs and separately installed wireproxy binaries are preserved.

## Reference

[Reference guide](GUIDE.md): advanced settings, connection lifecycle, development,
and validation. See the [changelog](CHANGELOG.md) and
[GitHub Releases](https://github.com/codexjdub/WireProxyTray/releases) for release history.

## License

[MIT](LICENSE) for WireProxyTray's original source. Bundled dependencies retain their own licenses; notices are in [licenses/](licenses/).
