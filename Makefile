GO ?= go
VERSION ?= dev

.PHONY: tray wireproxy package test check install uninstall
package:
	bash scripts/package.sh

wireproxy:
	GO=$(GO) bash scripts/build-wireproxy.sh

tray:
	CGO_ENABLED=0 $(GO) build -buildvcs=false -trimpath -ldflags='-s -w -X main.version=$(VERSION)' -o bin/wireproxy-tray ./cmd/wireproxy-tray

test:
	bash tests/cli.sh
	bash tests/install.sh
	$(GO) test -buildvcs=false ./...

check:
	bash -n bin/wireproxyctl scripts/*.sh tests/*.sh
	$(GO) vet -buildvcs=false ./...
	@if command -v shellcheck >/dev/null; then shellcheck bin/wireproxyctl scripts/*.sh tests/*.sh; fi

install:
	bash scripts/install.sh

uninstall:
	bash scripts/uninstall.sh
