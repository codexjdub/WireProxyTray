package main

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestPortValidationAndPersistence(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	for _, input := range []string{"", "80", "65536", "1.5", "-1080", "1080;echo bad"} {
		if _, err := ParsePort(input); err == nil {
			t.Fatalf("accepted %q", input)
		}
	}
	if n, err := ParsePort(" 01081\n"); err != nil || n != 1081 {
		t.Fatalf("%d %v", n, err)
	}
	if n, err := LoadPort(); err != nil || n != 1080 {
		t.Fatalf("default: %d %v", n, err)
	}
	if err := savePort(4242); err != nil {
		t.Fatal(err)
	}
	if n, err := LoadPort(); err != nil || n != 4242 {
		t.Fatalf("saved: %d %v", n, err)
	}
	path, _ := portFile()
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("permissions: %v %v", info, err)
	}
}

func TestCustomPortDialog(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	path := filepath.Join(dir, "zenity")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nprintf '4242\\n'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if n, err := askPort(context.Background(), 1080); err != nil || n != 4242 {
		t.Fatalf("%d %v", n, err)
	}
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 1\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if _, err := askPort(context.Background(), 1080); !errors.Is(err, ErrCancelled) {
		t.Fatalf("cancel: %v", err)
	}
}
