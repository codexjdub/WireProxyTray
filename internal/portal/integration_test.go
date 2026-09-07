//go:build integration

package portal

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

type fakePortal struct {
	conn *dbus.Conn
	code uint32
}

func (p *fakePortal) OpenFile(parent, title string, options map[string]dbus.Variant, sender dbus.Sender) (dbus.ObjectPath, *dbus.Error) {
	token := options["handle_token"].Value().(string)
	path := dbus.ObjectPath("/org/freedesktop/portal/desktop/request/" + strings.ReplaceAll(strings.TrimPrefix(string(sender), ":"), ".", "_") + "/" + token)
	// An immediate signal exercises the subscribe-before-call race.
	p.conn.Emit(path, "org.freedesktop.portal.Request.Response", p.code, map[string]dbus.Variant{"uris": dbus.MakeVariant([]string{"file:///tmp/vpn%20profile.conf"})})
	return path, nil
}

func TestPortalImmediateResponseAndCancellation(t *testing.T) {
	server, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	client, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	if _, err := server.RequestName("org.freedesktop.portal.Desktop", dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
	for _, code := range []uint32{0, 1} {
		if err := server.Export(&fakePortal{server, code}, "/org/freedesktop/portal/desktop", "org.freedesktop.portal.FileChooser"); err != nil {
			t.Fatal(err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		path, err := OpenConfig(ctx, client)
		cancel()
		if code == 0 && (err != nil || path != "/tmp/vpn profile.conf") {
			t.Fatalf("%q %v", path, err)
		}
		if code == 1 && err != ErrCancelled {
			t.Fatalf("expected cancellation, got %v", err)
		}
	}
}
