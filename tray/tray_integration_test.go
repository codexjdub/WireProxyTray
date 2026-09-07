//go:build integration

package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

type mockWatcher struct{ registrations chan string }

func (w *mockWatcher) RegisterStatusNotifierItem(path string, sender dbus.Sender) *dbus.Error {
	select {
	case w.registrations <- string(sender):
	default:
	}
	return nil
}

// Run from the repository root with make integration.
func TestTrayRegistrationStateAndHostRestart(t *testing.T) {
	root, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	w := &mockWatcher{make(chan string, 8)}
	if err := conn.Export(w, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher"); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.RequestName("org.kde.StatusNotifierWatcher", dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
	runtime := t.TempDir()
	if err := os.Chmod(runtime, 0700); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(filepath.Join(root, "build/wireproxy-tray"), "--cli", filepath.Join(root, "wireproxyctl"))
	tools := filepath.Join(runtime, "tools")
	if err := os.Mkdir(tools, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tools, "zenity"), []byte("#!/bin/sh\nprintf '4242\\n'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	cmd.Env = append(os.Environ(), "XDG_RUNTIME_DIR="+runtime, "XDG_CONFIG_HOME="+runtime, "PATH="+tools+":"+os.Getenv("PATH"))
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { cmd.Process.Kill(); cmd.Wait() }()
	var name string
	select {
	case name = <-w.registrations:
	case <-time.After(5 * time.Second):
		t.Fatal("tray did not register")
	}
	menu := conn.Object(name, "/StatusNotifierItem/menu")
	waitMenu := func(text string) {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			call := menu.Call("com.canonical.dbusmenu.GetLayout", 0, int32(0), int32(-1), []string{})
			if call.Err == nil && strings.Contains(fmt.Sprint(call.Body), text) {
				return
			}
			time.Sleep(30 * time.Millisecond)
		}
		t.Fatalf("menu never showed %q", text)
	}
	waitMenu("State: disconnected")
	type layout struct {
		ID         int32
		Properties map[string]dbus.Variant
		Children   []dbus.Variant
	}
	click := func(label string) {
		t.Helper()
		var revision uint32
		var tree layout
		if err := menu.Call("com.canonical.dbusmenu.GetLayout", 0, int32(0), int32(-1), []string{}).Store(&revision, &tree); err != nil {
			t.Fatal(err)
		}
		var find func(layout) int32
		find = func(node layout) int32 {
			if node.Properties["label"].Value() == label {
				return node.ID
			}
			for _, child := range node.Children {
				var nested layout
				if err := dbus.Store([]interface{}{child.Value()}, &nested); err != nil {
					t.Fatal(err)
				}
				if id := find(nested); id != 0 {
					return id
				}
			}
			return 0
		}
		id := find(tree)
		if id == 0 {
			t.Fatalf("menu item not found: %s", label)
		}
		if call := menu.Call("com.canonical.dbusmenu.Event", 0, id, "clicked", dbus.MakeVariant(int32(0)), uint32(0)); call.Err != nil {
			t.Fatal(call.Err)
		}
	}
	click("1081")
	waitMenu("Connect… (port 1081)")
	click("Custom…")
	waitMenu("Connect… (port 4242)")
	saved, err := os.ReadFile(filepath.Join(runtime, "wireproxyctl", "tray-port"))
	if err != nil || string(saved) != "4242\n" {
		t.Fatalf("saved port: %q %v", saved, err)
	}
	// Use this test process as a live foreground owner; no actual VPN is started.
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", os.Getpid()))
	if err != nil {
		t.Fatal(err)
	}
	stat := strings.Fields(string(data)[strings.LastIndex(string(data), ") ")+2:])
	state := fmt.Sprintf("1\nforeground\n/tmp/example.conf\n1080\n/bin/true\n%d\n%s\n", os.Getpid(), stat[19])
	stateFile := filepath.Join(runtime, "wireproxyctl", "state")
	if err := os.WriteFile(stateFile, []byte(state), 0600); err != nil {
		t.Fatal(err)
	}
	waitMenu("State: running")
	waitMenu("socks5h://127.0.0.1:1080")
	if err := os.Remove(stateFile); err != nil {
		t.Fatal(err)
	}
	waitMenu("State: disconnected")
	if _, err := conn.ReleaseName("org.kde.StatusNotifierWatcher"); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.RequestName("org.kde.StatusNotifierWatcher", dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
	select {
	case <-w.registrations:
	case <-time.After(3 * time.Second):
		t.Fatal("did not re-register after host restart")
	}
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	if err := cmd.Wait(); err != nil {
		t.Fatalf("unclean exit: %v %s", err, output.String())
	}
}
