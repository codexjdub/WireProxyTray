//go:build linux

package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/codexjdub/WireProxyTray/internal/control"
	"github.com/codexjdub/WireProxyTray/internal/tray"
	"github.com/godbus/dbus/v5"
)

var version = "dev"

func run() error {
	showVersion := flag.Bool("version", false, "Print the WireProxyTray version")
	cli := flag.String("cli", "", "Path to wireproxyctl (default: sibling executable or PATH)")
	port := flag.Int("port", 0, "SOCKS5 port (default: saved tray selection, or 1080)")
	flag.Parse()
	if *showVersion {
		fmt.Println("WireProxyTray " + version)
		return nil
	}
	override := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "port" {
			override = true
		}
	})
	if !override {
		var err error
		*port, err = tray.LoadPort()
		if err != nil {
			return fmt.Errorf("read saved port: %w", err)
		}
	}
	if *port < 1024 || *port > 65535 {
		return fmt.Errorf("port must be between 1024 and 65535")
	}
	if *cli == "" {
		executable, err := os.Executable()
		if err != nil {
			return err
		}
		sibling := filepath.Join(filepath.Dir(executable), "wireproxyctl")
		if info, err := os.Stat(sibling); err == nil && info.Mode()&0111 != 0 {
			*cli = sibling
		} else {
			*cli = "wireproxyctl"
		}
	}
	path, err := exec.LookPath(*cli)
	if err != nil {
		return fmt.Errorf("wireproxyctl not found; install the CLI or pass --cli PATH")
	}
	client := control.Client{Path: path}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	// Also prepares and validates the private runtime directory.
	if _, err := client.Status(ctx); err != nil {
		return err
	}
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return err
	}
	defer conn.Close()
	reply, err := conn.RequestName("io.github.wireproxyctl.Tray", dbus.NameFlagDoNotQueue)
	if err != nil {
		return err
	}
	if reply != dbus.RequestNameReplyPrimaryOwner {
		return fmt.Errorf("WireProxy tray is already running")
	}
	return tray.Run(ctx, conn, client, filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "wireproxyctl"), *port)
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "wireproxy-tray:", err)
		os.Exit(1)
	}
}
