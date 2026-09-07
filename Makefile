GO ?= go
VERSION ?= dev

.PHONY: tray wireproxy package test check integration install uninstall clean
package:
	bash scripts/package.sh

wireproxy:
	GO=$(GO) bash scripts/build-wireproxy.sh

tray:
	mkdir -p build
	CGO_ENABLED=0 $(GO) -C tray build -buildvcs=false -trimpath -ldflags='-s -w -X main.version=$(VERSION)' -o ../build/wireproxy-tray .

test: wireproxy tray
	bash tests/cli.sh
	bash tests/install.sh
	$(GO) -C tray test -buildvcs=false .

check:
	bash -n wireproxyctl scripts/*.sh tests/*.sh
	$(GO) -C tray vet -buildvcs=false .
	@if command -v shellcheck >/dev/null; then shellcheck wireproxyctl scripts/*.sh tests/*.sh; fi

integration: tray
	dbus-run-session -- $(GO) -C tray test -buildvcs=false -tags=integration .

install:
	bash scripts/install.sh

uninstall:
	bash scripts/uninstall.sh

clean:
	rm -rf -- build
