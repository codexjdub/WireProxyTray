package main

import "testing"

func TestLocalPath(t *testing.T) {
	for uri, want := range map[string]string{
		"file:///tmp/work%20vpn.conf":         "/tmp/work vpn.conf",
		"file://localhost/tmp/%23test.conf":   "/tmp/#test.conf",
		"file:///tmp/%24%28echo%20no%29.conf": "/tmp/$(echo no).conf",
	} {
		got, err := LocalPath(uri)
		if err != nil || got != want {
			t.Fatalf("%s: %q %v", uri, got, err)
		}
	}
	for _, uri := range []string{"https://example.com/vpn.conf", "file://remote/tmp/vpn.conf", "file:relative.conf", "file:///tmp/a%00b", "file:///tmp/test?query=1"} {
		if _, err := LocalPath(uri); err == nil {
			t.Fatalf("accepted %s", uri)
		}
	}
}
