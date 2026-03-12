PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
TARGET_NAME ?= owg

.PHONY: install uninstall

install:
	BINDIR="$(BINDIR)" TARGET_NAME="$(TARGET_NAME)" ./scripts/install.sh

uninstall:
	BINDIR="$(BINDIR)" TARGET_NAME="$(TARGET_NAME)" ./scripts/uninstall.sh
