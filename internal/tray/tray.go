package tray

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"html"
	"image"
	"image/color"
	"image/png"
	"log"
	"strconv"
	"time"

	"fyne.io/systray"
	"github.com/godbus/dbus/v5"

	"github.com/codexjdub/WireProxyTray/internal/control"
	"github.com/codexjdub/WireProxyTray/internal/portal"
)

type result struct {
	state control.State
	err   error
}

func icon(running bool) []byte {
	img := image.NewRGBA(image.Rect(0, 0, 32, 32))
	c := color.RGBA{155, 164, 175, 255}
	if running {
		c = color.RGBA{73, 190, 128, 255}
	}
	// A simple keyhole badge, generated once per state rather than loaded from a theme.
	for y := 3; y < 29; y++ {
		for x := 3; x < 29; x++ {
			if (x-16)*(x-16)+(y-16)*(y-16) < 169 {
				img.Set(x, y, c)
			}
		}
	}
	for y := 9; y < 24; y++ {
		for x := 11; x < 21; x++ {
			if (x-16)*(x-16)+(y-13)*(y-13) < 20 || (y >= 14 && x >= 14 && x <= 17) {
				img.Set(x, y, color.RGBA{30, 36, 43, 255})
			}
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

func notify(ctx context.Context, conn *dbus.Conn, text string) {
	log.Print(text)
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	conn.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications").CallWithContext(ctx,
		"org.freedesktop.Notifications.Notify", 0, "WireProxy", uint32(0), "network-vpn", "WireProxy", html.EscapeString(text), []string{}, map[string]dbus.Variant{}, int32(8000))
}

func Run(ctx context.Context, conn *dbus.Conn, client control.Client, directory string, port int) error {
	wake := make(chan struct{}, 1)
	if err := Watch(ctx, conn, directory, wake); err != nil {
		return err
	}
	systray.Run(func() {
		systray.SetTitle("WireProxy")
		off, on := icon(false), icon(true)
		systray.SetIcon(off)
		status := systray.AddMenuItem("Reading status…", "Process status, not tunnel verification")
		status.Disable()
		address := systray.AddMenuItem("No proxy", "Set your application to use this address")
		address.Disable()
		config := systray.AddMenuItem("No config", "Original WireGuard configuration")
		config.Disable()
		systray.AddSeparator()
		connect := systray.AddMenuItem(fmt.Sprintf("Connect… (port %d)", port), "Choose a regular WireGuard config")
		portMenu := systray.AddMenuItem(fmt.Sprintf("Proxy port: %d", port), "Applies to the next connection; does not interrupt an active connection")
		portChanges := make(chan int, 1)
		presets := map[int]*systray.MenuItem{}
		for _, n := range []int{1080, 1081, 1082, 8080, 9050} {
			item := portMenu.AddSubMenuItemCheckbox(strconv.Itoa(n), "Use this port for the next connection", n == port)
			presets[n] = item
			go func(n int, item *systray.MenuItem) {
				for {
					select {
					case <-ctx.Done():
						return
					case <-item.ClickedCh:
						select {
						case portChanges <- n:
						case <-ctx.Done():
							return
						}
					}
				}
			}(n, item)
		}
		customPort := portMenu.AddSubMenuItem("Custom…", "Enter another port using an on-demand Zenity dialog")
		disconnect := systray.AddMenuItem("Disconnect", "Stop wireproxy")
		check := systray.AddMenuItem("Check connection", "Contact api.ipify.org through the proxy")
		refresh := systray.AddMenuItem("Refresh status", "Read current process state")
		systray.AddSeparator()
		quit := systray.AddMenuItem("Quit tray", "Leave any connection running")
		results := make(chan result, 1)
		actions := make(chan error, 1)
		go func() {
			busy, reading, pending := false, false, false
			current := control.State{}
			refreshStatus := func() {
				if reading {
					pending = true
					return
				}
				reading = true
				go func() {
					state, err := client.Status(ctx)
					select {
					case results <- result{state, err}:
					case <-ctx.Done():
					}
				}()
			}
			update := func() {
				connect.SetTitle(fmt.Sprintf("Connect… (port %d)", port))
				portMenu.SetTitle(fmt.Sprintf("Proxy port: %d", port))
				for n, item := range presets {
					if n == port {
						item.Check()
					} else {
						item.Uncheck()
					}
				}
				if busy {
					portMenu.Disable()
				} else {
					portMenu.Enable()
				}
				status.SetTitle("State: " + current.Status)
				if current.Proxy != "" {
					address.SetTitle(current.Proxy)
				} else {
					address.SetTitle("No proxy")
				}
				if current.Config != "" {
					config.SetTitle(current.Config)
				} else {
					config.SetTitle("No config")
				}
				systray.SetTooltip("WireProxy · " + current.Status)
				if current.Status == "running" {
					systray.SetIcon(on)
				} else {
					systray.SetIcon(off)
				}
				connect.Disable()
				disconnect.Disable()
				check.Disable()
				if !busy {
					if current.Status == "disconnected" || current.Status == "failed" {
						connect.Enable()
					}
					if current.Mode != "" {
						disconnect.Enable()
					}
					if current.Status == "running" {
						check.Enable()
					}
				}
			}
			action := func(fn func() error) {
				if busy {
					return
				}
				busy = true
				update()
				go func() {
					err := fn()
					select {
					case actions <- err:
					case <-ctx.Done():
					}
				}()
			}
			refreshStatus()
			for {
				select {
				case <-ctx.Done():
					systray.Quit()
					return
				case <-quit.ClickedCh:
					systray.Quit()
					return
				case <-wake:
					refreshStatus()
				case <-refresh.ClickedCh:
					refreshStatus()
				case <-systray.TrayOpenedCh:
					refreshStatus()
				case r := <-results:
					reading = false
					if r.err != nil {
						current = control.State{Status: "unknown"}
						status.SetTooltip(r.err.Error())
					} else {
						current = r.state
					}
					update()
					if pending {
						pending = false
						refreshStatus()
					}
				case err := <-actions:
					busy = false
					if err != nil && !errors.Is(err, portal.ErrCancelled) {
						go notify(ctx, conn, err.Error())
					}
					update()
					refreshStatus()
				case n := <-portChanges:
					if err := savePort(n); err != nil {
						go notify(ctx, conn, "Could not save port: "+err.Error())
					} else {
						port = n
					}
					update()
				case <-customPort.ClickedCh:
					selected := port
					action(func() error {
						dialogCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
						defer cancel()
						n, err := askPort(dialogCtx, selected)
						if err != nil {
							return err
						}
						select {
						case portChanges <- n:
						case <-ctx.Done():
							return ctx.Err()
						}
						return nil
					})
				case <-connect.ClickedCh:
					selected := port
					action(func() error {
						chooserCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
						defer cancel()
						path, err := portal.OpenConfig(chooserCtx, conn)
						if err != nil {
							return err
						}
						_, err = client.Run(ctx, "connect", path, "--port", strconv.Itoa(selected))
						return err
					})
				case <-disconnect.ClickedCh:
					action(func() error { _, err := client.Run(ctx, "disconnect"); return err })
				case <-check.ClickedCh:
					action(func() error {
						text, err := client.Run(ctx, "check")
						if err == nil {
							notify(ctx, conn, text)
						}
						return err
					})
				}
			}
		}()
	}, func() {})
	return nil
}
