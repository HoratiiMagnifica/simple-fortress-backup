# Makefile - FortressBackup management commands

.PHONY: help server client web uninstall backup-add backup-list

help:
	@echo "FortressBackup - Secure Automated Backups"
	@echo ""
	@echo "Available commands:"
	@echo "  make server          - Install backup server (storage)"
	@echo "  make client          - Install backup client (source)"
	@echo "  make web             - Install web management interface"
	@echo "  make backup-add      - Add a new backup job (interactive)"
	@echo "  make backup-list     - List all backup jobs"
	@echo "  make uninstall       - Completely remove FortressBackup"
	@echo ""

server:
	@echo "Installing FortressBackup server..."
	@sudo bash server/install.sh

client:
	@echo "Installing FortressBackup client..."
	@sudo bash client/install.sh

web:
	@echo "Installing web interface..."
	@cd web && sudo bash installer.sh

backup-add:
	@echo "Adding new backup job..."
	@sudo bash scripts/backup-add.sh

backup-list:
	@echo "Listing backup jobs..."
	@sudo bash scripts/backup-list.sh

uninstall:
	@echo "Removing FortressBackup..."
	@if [ -f scripts/uninstall.sh ]; then \
		sudo bash scripts/uninstall.sh; \
	elif [ -f uninstall.sh ]; then \
		sudo bash uninstall.sh; \
	else \
		echo "Uninstall script not found!"; \
	fi