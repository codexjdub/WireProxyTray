package main

import (
	"context"
	"fmt"
	"path/filepath"

	"github.com/fsnotify/fsnotify"
	"github.com/godbus/dbus/v5"
)

// Watch is event-driven: filesystem commits cover CLI changes; systemd covers crashes/retries.
func Watch(ctx context.Context, conn *dbus.Conn, directory string, wake chan<- struct{}) error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	if err := watcher.Add(directory); err != nil {
		watcher.Close()
		return err
	}
	signals := make(chan *dbus.Signal, 32)
	conn.Signal(signals)
	opts := []dbus.MatchOption{dbus.WithMatchSender("org.freedesktop.systemd1"), dbus.WithMatchInterface("org.freedesktop.DBus.Properties"), dbus.WithMatchMember("PropertiesChanged"), dbus.WithMatchObjectPath("/org/freedesktop/systemd1/unit/wireproxyctl_2eservice")}
	if err := conn.AddMatchSignal(opts...); err != nil {
		watcher.Close()
		conn.RemoveSignal(signals)
		return err
	}
	// No systemd is fine for foreground-only use. File events still update the tray.
	conn.Object("org.freedesktop.systemd1", "/org/freedesktop/systemd1").CallWithContext(ctx, "org.freedesktop.systemd1.Manager.Subscribe", 0)
	notify := func() {
		select {
		case wake <- struct{}{}:
		default:
		}
	}
	go func() {
		defer watcher.Close()
		defer conn.RemoveSignal(signals)
		defer conn.RemoveMatchSignal(opts...)
		for {
			select {
			case <-ctx.Done():
				return
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}
				if filepath.Base(event.Name) == "state" && event.Op&(fsnotify.Create|fsnotify.Rename|fsnotify.Remove|fsnotify.Write) != 0 {
					notify()
				}
			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				fmt.Printf("State watcher: %v\n", err)
				notify()
			case _, ok := <-signals:
				if !ok {
					return
				}
				notify()
			}
		}
	}()
	return nil
}
