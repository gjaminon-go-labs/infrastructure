# Infrastructure Makefile

.DEFAULT_GOAL := help

help:
	@echo "Available commands:"
	@echo "  setup-dev-db     - Create/update development database (go-labs-dev)"
	@echo "  install-postgres - Install PostgreSQL 16 (only if not already installed)"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Run from infrastructure/ directory"
	@echo "  - sudo access required for PostgreSQL installation"

setup-dev-db:
	@echo "Setting up development database..."
	@if [ ! -f "scripts/provision-database.sh" ]; then \
		echo "❌ Error: provision-database.sh not found"; \
		echo "   Please run this command from the infrastructure/ directory"; \
		exit 1; \
	fi
	@echo "📊 Creating go-labs-dev database with billing schema and users..."
	@echo "y" | ./scripts/provision-database.sh dev || true
	@echo "✅ Development database setup complete!"

install-postgres:
	@echo "Checking PostgreSQL installation..."
	@if systemctl is-active --quiet postgresql 2>/dev/null; then \
		echo "✅ PostgreSQL is already running"; \
		systemctl status postgresql --no-pager --lines=3; \
	elif command -v psql >/dev/null 2>&1 && pg_isready >/dev/null 2>&1; then \
		echo "✅ PostgreSQL is already installed and running"; \
	else \
		echo "📦 Installing PostgreSQL 16..."; \
		if [ ! -f "scripts/install-postgresql16.sh" ]; then \
			echo "❌ Error: install-postgresql16.sh not found"; \
			echo "   Please run this command from the infrastructure/ directory"; \
			exit 1; \
		fi; \
		sudo ./scripts/install-postgresql16.sh; \
		echo "✅ PostgreSQL 16 installation complete!"; \
	fi

.PHONY: help setup-dev-db install-postgres