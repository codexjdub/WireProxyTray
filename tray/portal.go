// The portal client opens the user's desktop file chooser over D-Bus.
package main

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync/atomic"

	"github.com/godbus/dbus/v5"
)

var ErrCancelled = errors.New("file selection cancelled")
var sequence atomic.Uint64

func LocalPath(uri string) (string, error) {
	u, err := url.Parse(uri)
	if err != nil {
		return "", err
	}
	if u.Scheme != "file" || (u.Host != "" && u.Host != "localhost") || !strings.HasPrefix(u.Path, "/") || u.RawQuery != "" || u.Fragment != "" {
		return "", errors.New("select a local WireGuard config file")
	}
	if strings.ContainsRune(u.Path, 0) {
		return "", errors.New("invalid file path")
	}
	return u.Path, nil
}

func OpenConfig(ctx context.Context, conn *dbus.Conn) (string, error) {
	token := fmt.Sprintf("wireproxyctl_%d", sequence.Add(1))
	sender := strings.ReplaceAll(strings.TrimPrefix(conn.Names()[0], ":"), ".", "_")
	expected := dbus.ObjectPath("/org/freedesktop/portal/desktop/request/" + sender + "/" + token)
	signals := make(chan *dbus.Signal, 8)
	conn.Signal(signals)
	defer conn.RemoveSignal(signals)
	opts := []dbus.MatchOption{dbus.WithMatchSender("org.freedesktop.portal.Desktop"), dbus.WithMatchInterface("org.freedesktop.portal.Request"), dbus.WithMatchMember("Response")}
	if err := conn.AddMatchSignal(opts...); err != nil {
		return "", err
	}
	defer conn.RemoveMatchSignal(opts...)
	options := map[string]dbus.Variant{
		"handle_token": dbus.MakeVariant(token), "multiple": dbus.MakeVariant(false),
		"directory": dbus.MakeVariant(false), "modal": dbus.MakeVariant(false),
		"accept_label": dbus.MakeVariant("Connect"),
	}
	var handle dbus.ObjectPath
	err := conn.Object("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop").CallWithContext(ctx,
		"org.freedesktop.portal.FileChooser.OpenFile", 0, "", "Select WireGuard configuration", options).Store(&handle)
	if err != nil {
		return "", fmt.Errorf("desktop file picker unavailable: %w", err)
	}
	for {
		select {
		case <-ctx.Done():
			conn.Object("org.freedesktop.portal.Desktop", handle).Go("org.freedesktop.portal.Request.Close", 0, nil)
			return "", ctx.Err()
		case sig := <-signals:
			if sig == nil {
				return "", errors.New("desktop bus closed")
			}
			if sig.Path != handle && sig.Path != expected {
				continue
			}
			if len(sig.Body) != 2 {
				return "", errors.New("invalid portal response")
			}
			code, ok := sig.Body[0].(uint32)
			if !ok {
				return "", errors.New("invalid portal result code")
			}
			if code == 1 {
				return "", ErrCancelled
			}
			if code != 0 {
				return "", errors.New("desktop file picker failed")
			}
			results, ok := sig.Body[1].(map[string]dbus.Variant)
			if !ok {
				return "", errors.New("invalid portal result")
			}
			uris, ok := results["uris"].Value().([]string)
			if !ok || len(uris) != 1 {
				return "", errors.New("select exactly one config file")
			}
			return LocalPath(uris[0])
		}
	}
}
