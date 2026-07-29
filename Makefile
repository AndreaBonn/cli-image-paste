# Makefile per cli-image-paste
#
# Esiste per i packager: un pacchetto .deb, un PKGBUILD o una derivazione Nix
# hanno bisogno di installare in una radice arbitraria senza toccare $HOME e
# senza fare domande. install.sh resta la via per gli utenti, perché configura
# anche la scorciatoia e chiede il consenso per le dipendenze.

PREFIX ?= /usr/local
DESTDIR ?=
BINDIR = $(DESTDIR)$(PREFIX)/bin
DOCDIR = $(DESTDIR)$(PREFIX)/share/doc/cli-image-paste
EXAMPLEDIR = $(DESTDIR)$(PREFIX)/share/cli-image-paste

BIN = paste-image
DIST = dist/$(BIN)
SOURCES = $(wildcard lib/*.sh)

.PHONY: all build test lint install uninstall clean help

all: build

# L'artefatto si ricostruisce quando un modulo è più recente: senza questa
# dipendenza un packager potrebbe impacchettare una build stantia.
$(DIST): $(SOURCES) scripts/build.sh
	bash scripts/build.sh

build: $(DIST)

test:
	bash tests/run_tests.sh

lint:
	shellcheck $(DIST) lib/*.sh scripts/*.sh install.sh uninstall.sh \
		tests/*.sh tests/framework/*.sh

install: build
	install -d $(BINDIR)
	install -m 755 $(DIST) $(BINDIR)/$(BIN)
	install -d $(EXAMPLEDIR)
	install -m 644 config.example $(EXAMPLEDIR)/config.example
	install -d $(DOCDIR)
	install -m 644 README.md README.it.md SECURITY.md SECURITY.it.md \
		CHANGELOG.md LICENSE $(DOCDIR)/

uninstall:
	rm -f $(BINDIR)/$(BIN)
	rm -rf $(EXAMPLEDIR)
	rm -rf $(DOCDIR)

clean:
	rm -rf dist

help:
	@echo "Target disponibili:"
	@echo "  build      Genera dist/paste-image dai moduli in lib/"
	@echo "  test       Esegue la suite completa con i suoi gate"
	@echo "  lint       ShellCheck su tutti i percorsi"
	@echo "  install    Installa in \$$PREFIX (default /usr/local), rispetta \$$DESTDIR"
	@echo "  uninstall  Rimuove quanto installato da 'make install'"
	@echo "  clean      Rimuove l'artefatto generato"
	@echo ""
	@echo "Per un'installazione utente con scorciatoia: bash install.sh"
