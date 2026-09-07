# WireProxyTray

A lean Linux controller for [wireproxy](https://github.com/windtf/wireproxy): an editable **Bash CLI**, plus an optional **Go system tray**. Inspired by [WireProxyMenu](https://github.com/codexjdub/WireProxyMenu); this is an independent implementation.

Point it at an ordinary WireGuard configuration. It generates the proxy settings and leaves your original file untouched. One connection runs at a time.

## CLI

```sh
wireproxyctl connect ~/vpn/work.conf
wireproxyctl connect ~/vpn/work.conf --port 1081
wireproxyctl status
wireproxyctl check
wireproxyctl logs
wireproxyctl disconnect
```

Default listener: `127.0.0.1:1080`, SOCKS5. Set individual apps to use that proxy; the tool does not change system routes or system proxy settings.

For direct operation without systemd:

```sh
wireproxyctl connect ~/vpn/work.conf --foreground
```

Ctrl+C stops the process and removes the companion. Another terminal can also run `disconnect`. Foreground mode forwards wireproxy output and exit status; it does not automatically restart the process. `logs` and `logs --follow` read the background service's journal.

`status` distinguishes running, reconnecting, stopping, failed, disconnected, and unknown. **Running means a process is running**, not that the VPN passes traffic. `check` explicitly sends one HTTPS request to `api.ipify.org` through the SOCKS5 proxy and reports the resulting IP. It ignores curlrc and overrides `NO_PROXY`, using proxy-side DNS. No periodic network probes run.

## Install

Download a package from [GitHub Releases](https://github.com/codexjdub/WireProxyTray/releases):

| Architecture | Package | Validation |
|---|---|---|
| AMD64 / x86-64 | `wireproxyctl-linux-amd64.tar.gz` | Local CLI, SOCKS5, systemd and D-Bus integration tested |
| ARM64 / AArch64 | `wireproxyctl-linux-arm64.tar.gz` | Cross-compiled; **not runtime-tested** |

Download the matching `.sha256` file, then verify and extract (AMD64 example):

```sh
sha256sum -c wireproxyctl-linux-amd64.tar.gz.sha256
tar -xzf wireproxyctl-linux-amd64.tar.gz
cd wireproxyctl
```

Use the ARM64 filenames on ARM64. The GitHub **Source code** downloads contain source only; choose the named release package to get the executables.

The distribution includes a pinned, standalone wireproxy executable. No separate wireproxy download or Go installation is needed to install and run it.

Other runtime CLI dependencies:

- Bash 4.4+, GNU coreutils (including `timeout`), awk, `flock` (util-linux), `ss` (iproute2).
- systemd with a user manager for background mode; not needed for foreground mode.
- curl only for `check`.

From an extracted distribution (or a checkout after building both binaries):

```sh
bash scripts/install.sh
```

This installs `~/.local/bin/wireproxyctl`, its private wireproxy executable under `~/.local/libexec/wireproxyctl/`, and a user service under `~/.config/systemd/user/` (respecting `XDG_CONFIG_HOME`). Ensure `~/.local/bin` is on PATH. No root access, service startup, or login autostart is requested by the installer. Users operate the service through the CLI. Existing system or user-installed wireproxy binaries are not replaced.

The installer checks the bundled executable's SHA-256 and target architecture before installation. Build provenance and license notices are installed alongside it. This bundle pins windtf/wireproxy commit `70dabd8db2cb9e0cf4f3d3b9f528fb8637ad3379`, which was used for the integration tests; it is a source snapshot, not a claimed upstream release version.

To use an alternate binary:

```sh
WIREPROXY_BINARY=/path/to/wireproxy wireproxyctl connect ~/vpn/work.conf
```

An explicit `WIREPROXY_BINARY` takes precedence over the bundle; PATH is used only when no bundle is present. The selected absolute executable path is remembered for that connection. The script reads runtime metadata as plain data; it never sources the config or metadata as shell code.

## Optional tray

The tray uses `fyne.io/systray` and D-Bus StatusNotifier/DBusMenu. **It is not specific to any distribution or bar.** It requires a StatusNotifier-capable host (such as Plasma's tray or a compatible bar); GNOME may need a tray extension. Legacy XEmbed-only trays are not supported directly.

For the file picker, your session needs `xdg-desktop-portal` with a working FileChooser backend. Notifications use the standard desktop notification service. No GTK or Qt toolkit is linked into the helper; the file picker runs through your desktop's portal.

The distribution includes a prebuilt tray. Install it alongside the CLI:

```sh
bash scripts/install.sh --tray
wireproxy-tray
```

The helper can also run directly from the checkout:

```sh
bin/wireproxy-tray --cli "$PWD/bin/wireproxyctl"
```

Choose **Proxy port** in the tray menu to select a preset (1080, 1081, 1082, 8080, or 9050), or **Custom…** to enter any port from 1024 to 65535. Custom entry uses the optional `zenity` utility only while the dialog is open; presets need no dialog dependency. The selected port is saved in `$XDG_CONFIG_HOME/wireproxyctl/tray-port` (normally `~/.config/wireproxyctl/tray-port`). Changes apply to the next connection and do not interrupt a running proxy. `--port 1081` overrides the saved value for that launch.

The menu also includes **Connect**, **Disconnect**, **Check connection**, **Refresh status**, and **Quit tray**, plus the current state, config path, and proxy address. Green means the process is running; it is not a VPN health assertion. Quit tray leaves a running connection alone. Only one tray instance is allowed per session bus.

The tray calls the Bash CLI for all connection operations. It watches filesystem changes and systemd D-Bus signals, and refreshes when you open the menu. There is no periodic status timer. StatusNotifier registration is renewed when the tray host restarts.

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

## Remove

```sh
bash scripts/uninstall.sh
```

This stops the managed connection and removes the CLI, bundled wireproxy, tray executable/launcher and service. Your original WireGuard configs and any separately installed wireproxy binaries are preserved. The installer and uninstaller accept matching `--prefix`, `--unit-dir`, and `--destdir` options for custom locations or packaging. Close the tray before uninstalling if `busctl` is unavailable.

## Development and tests

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

## License

WireProxyTray's original source is MIT-licensed. Wireproxy and other bundled dependencies retain their own licenses; their notices are included under `libexec/wireproxyctl/licenses/` and `licenses/tray/`.
