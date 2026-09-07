package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

func ParsePort(text string) (int, error) {
	text = strings.TrimSpace(text)
	if text == "" || len(text) > 5 || strings.IndexFunc(text, func(r rune) bool { return r < '0' || r > '9' }) >= 0 {
		return 0, fmt.Errorf("enter a port number between 1024 and 65535")
	}
	n, err := strconv.Atoi(text)
	if err != nil || n < 1024 || n > 65535 {
		return 0, fmt.Errorf("enter a port number between 1024 and 65535")
	}
	return n, nil
}

func portFile() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "wireproxyctl", "tray-port"), nil
}

func LoadPort() (int, error) {
	path, err := portFile()
	if err != nil {
		return 0, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return 1080, nil
	}
	if err != nil {
		return 0, err
	}
	return ParsePort(string(data))
}

func savePort(n int) error {
	path, err := portFile()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".tray-port-")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	_, err = fmt.Fprintf(f, "%d\n", n)
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(f.Name(), path)
}

func askPort(ctx context.Context, current int) (int, error) {
	program, err := exec.LookPath("zenity")
	if err != nil {
		return 0, fmt.Errorf("custom port entry needs Zenity; install zenity or choose a preset from the Proxy port menu")
	}
	for {
		cmd := exec.CommandContext(ctx, program, "--entry", "--title=WireProxy port", "--text=SOCKS5 port for the next connection (1024–65535)", "--entry-text="+strconv.Itoa(current))
		out, err := cmd.Output()
		if err != nil {
			var exit *exec.ExitError
			if errors.As(err, &exit) && exit.ExitCode() == 1 {
				return 0, ErrCancelled
			}
			return 0, fmt.Errorf("could not open port dialog: %w", err)
		}
		n, err := ParsePort(string(out))
		if err == nil {
			return n, nil
		}
		if err := exec.CommandContext(ctx, program, "--error", "--text=Enter a whole number between 1024 and 65535.").Run(); err != nil {
			return 0, err
		}
	}
}
