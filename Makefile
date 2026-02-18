PREFIX ?= /root/.local
BINDIR ?= $(PREFIX)/bin

SCRIPTS = btrfs_backup.sh btrfs_snapshot.sh btrfs_snapshot_cleanup.sh mount_btrfs_subvolumes.sh
LIBS = common.sh
CONFIG = config.sh

INSTALL = install
INSTALL_PROGRAM = $(INSTALL) -m 755
INSTALL_DATA = $(INSTALL) -m 644

.PHONY: all
all:
	@echo "Btrfs Backup Scripts"
	@echo "Usage:"
	@echo "  make install [PREFIX=/path/to/prefix] [DESTDIR=/path/to/destdir]"
	@echo ""
	@echo "Default PREFIX is /root/.local"
	@echo "Scripts will be installed to (DESTDIR)(BINDIR)"

.PHONY: install
install:
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL_PROGRAM) $(SCRIPTS) $(DESTDIR)$(BINDIR)
	$(INSTALL_DATA) $(LIBS) $(DESTDIR)$(BINDIR)
	@if [ ! -f $(DESTDIR)$(BINDIR)/$(CONFIG) ]; then \
		$(INSTALL_DATA) $(CONFIG) $(DESTDIR)$(BINDIR); \
		echo "Installed default $(CONFIG) to $(DESTDIR)$(BINDIR)"; \
	else \
		echo "Skipping $(CONFIG) installation: file already exists in $(DESTDIR)$(BINDIR)"; \
	fi

.PHONY: uninstall
uninstall:
	@for f in $(SCRIPTS) $(LIBS) $(CONFIG); do \
		echo "Removing $(DESTDIR)$(BINDIR)/$$f"; \
		rm -f $(DESTDIR)$(BINDIR)/$$f; \
	done
