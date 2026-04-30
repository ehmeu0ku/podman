# Makefile for podman
# See docs/make.md for usage

export GOPROXY ?= https://proxy.golang.org

GO ?= go
GOFLAGS ?= -trimpath
GOTAGS ?= $(shell hack/btrfs_tag.sh) $(shell hack/btrfs_installed_tag.sh) $(shell hack/ostree_tag.sh) $(shell hack/selinux_tag.sh) $(shell hack/apparmor_tag.sh) $(shell hack/systemd_tag.sh)
GOBINDIR := $(shell $(GO) env GOBIN)
GOPATH := $(shell $(GO) env GOPATH)
GOOS := $(shell $(GO) env GOOS)
GOARCH := $(shell $(GO) env GOARCH)

# Use nproc to parallelize builds; fall back to 4 if nproc is unavailable
NPROC ?= $(shell nproc 2>/dev/null || echo 4)

BINDIR ?= /usr/local/bin
LIBEXECDIR ?= /usr/local/libexec
MANDIR ?= /usr/local/share/man
SHAREDIR ?= /usr/local/share
ETCDIR ?= /etc
TMPFILESDIR ?= /usr/lib/tmpfiles.d
SYSTEMDDIR ?= /usr/lib/systemd/system
USERSYSTEMDDIR ?= /usr/lib/systemd/user

BUILD_TAGS ?= $(GOTAGS)
LDFLAGS_PODMAN ?= $(LDFLAGS)
DEFINES_PODMAN ?= -X main.buildInfo=$(shell date +%s) \
		  -X main.gitCommit=$(shell git rev-parse HEAD 2>/dev/null) \
		  -X main.gitTreeState=$(shell if git diff --quiet 2>/dev/null; then echo clean; else echo dirty; fi)

PODMAN_VERSION ?= $(shell cat version/version.go | grep -o '".*"' | tr -d '"')

PACKAGES := $(shell $(GO) list -tags "$(GOTAGS)" ./...)

BINARY := bin/podman
REMOTE_BINARY := bin/podman-remote

.DEFAULT_GOAL := all

.PHONY: all
all: binaries docs

.PHONY: binaries
binaries: podman podman-remote ## Build podman and podman-remote binaries

.PHONY: podman
podman: ## Build the podman binary
	$(GO) build \
		$(GOFLAGS) \
		-tags "$(BUILD_TAGS)" \
		-ldflags "$(LDFLAGS_PODMAN) $(DEFINES_PODMAN)" \
		-o $(BINARY) \
		./cmd/podman

.PHONY: podman-remote
podman-remote: ## Build the podman-remote binary
	$(GO) build \
		$(GOFLAGS) \
		-tags "$(BUILD_TAGS) remote" \
		-ldflags "$(LDFLAGS_PODMAN) $(DEFINES_PODMAN)" \
		-o $(REMOTE_BINARY) \
		./cmd/podman

.PHONY: test
test: unit integration ## Run all tests

.PHONY: unit
unit: ## Run unit tests
	$(GO) test -tags "$(GOTAGS)" -p $(NPROC) $(PACKAGES)

.PHONY: integration
integration: ## Run integration tests
	$(GO) test -tags "$(GOTAGS) integration" ./test/...

.PHONY: lint
lint: ## Run golangci-lint
	golangci-lint run --timeout 10m

.PHONY: vendor
vendor: ## Update vendor directory
	$(GO) mod tidy
	$(GO) mod vendor
	$(GO) mod verify

.PHONY: fmt
fmt: ## Format Go source code
	gofmt -l -w $(shell find . -name '*.go' -not -path './vendor/*')

.PHONY: clean
clean: ## Remove build artifacts
	rm -rf bin/
	rm -rf _output/

.PHONY: install
install: ## Install podman binary
	install -d $(DESTDIR)/$(BINDIR)
	install -m 755 $(BINARY) $(DESTDIR)/$(BINDIR)/podman

# Also install podman-remote when running 'make install', useful for my dev workflow
.PHONY: install-remote
install-remote: podman-remote ## Install podman-remote binary
	install -d $(DESTDIR)/$(BINDIR)
	install -m 755 $(REMOTE_BINARY) $(DESTDIR)/$(BINDIR)/podman-remote

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
