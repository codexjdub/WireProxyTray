package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestParseState(t *testing.T) {
	s, err := ParseState([]byte(`{"status":"running","config":"/tmp/a \"b.conf","mode":"foreground","proxy":"socks5h://127.0.0.1:1080"}`))
	if err != nil || s.Config != "/tmp/a \"b.conf" {
		t.Fatalf("%+v %v", s, err)
	}
	if _, err := ParseState([]byte(`{"status":"connected"}`)); err == nil {
		t.Fatal("accepted unknown state")
	}
	if _, err := ParseState([]byte(`broken`)); err == nil {
		t.Fatal("accepted invalid JSON")
	}
}

func TestCommandArgumentsAreNotShellCode(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "cli with spaces")
	if err := os.WriteFile(path, []byte("#!/bin/bash\nprintf '%s' \"$2\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	value := "/tmp/vpn $(touch SHOULD_NOT_EXIST); 'quoted'.conf"
	out, err := (Client{Path: path}).Run(context.Background(), "connect", value)
	if err != nil || out != value {
		t.Fatalf("%q %v", out, err)
	}
}
