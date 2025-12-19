.PHONY: help validate lint test build build-docker up down logs clean generate-override setup-permissions validate-env setup start health secret verify

.DEFAULT_GOAL := help

-include .env
export

# ============================================================================
# CI/CD Standard Targets (Required by Specification)
# ============================================================================

validate: ## Run code validation (fmt, vet)
	@echo "Running validation..."
	@go fmt ./...
	@go vet ./...
	@echo "✓ Validation passed"

lint: ## Run linters
	@echo "Running linters..."
	@which golangci-lint > /dev/null || (echo "ERROR: golangci-lint not installed. Run: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest" && exit 1)
	@golangci-lint run --timeout=5m
	@echo "✓ Lint passed"

test: ## Run all tests (unit + integration)
	@echo "Running tests..."
	@go test -v -race -coverprofile=coverage.txt -covermode=atomic ./...
	@echo "✓ Tests passed"

audit: ## Run security audits (govulncheck + gosec)
	@echo "Running security audits..."
	@echo "Checking for vulnerable dependencies..."
	@which govulncheck > /dev/null || go install golang.org/x/vuln/cmd/govulncheck@latest
	@govulncheck ./...
	@echo "Running security linter..."
	@which gosec > /dev/null || go install github.com/securego/gosec/v2/cmd/gosec@latest
	@gosec -quiet ./...
	@echo "✓ Security audit passed"

build: ## Build daemon binary to dist/storage-sage
	@echo "Building storage-sage daemon..."
	@mkdir -p dist
	@CGO_ENABLED=1 go build -v -o dist/storage-sage ./cmd/storage-sage
	@CGO_ENABLED=1 go build -v -o dist/storage-sage-query ./cmd/storage-sage-query
	@echo "✓ Build complete: dist/storage-sage"
	@ls -lh dist/

build-frontend: ## Build frontend assets (Vite)
	@echo "Building frontend..."
	@cd web/frontend && \
		if [ ! -d "node_modules" ]; then \
			echo "Installing frontend dependencies..."; \
			npm install; \
		fi && \
		npm run build
	@echo "✓ Frontend build complete: web/frontend/dist/"
	@ls -lh web/frontend/dist/ | head -10

# ============================================================================
# Docker Management Targets
# ============================================================================

help: ## Show this help message
	@echo "StorageSage Build & Docker Management"
	@echo ""
	@echo "CI/CD Targets:"
	@echo "  make validate   - Run code validation (fmt, vet)"
	@echo "  make lint       - Run linters"
	@echo "  make test       - Run all tests"
	@echo "  make build      - Build binaries to dist/"
	@echo ""
	@echo "Docker Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v "^validate:" | grep -v "^lint:" | grep -v "^test:" | grep -v "^build:" | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Initial setup (create .env, generate certs, create config)
	@echo "Setting up StorageSage..."
	@if [ ! -f .env ]; then \
		cp .env.example .env 2>/dev/null || (echo "ERROR: .env.example not found. Please create .env manually." && exit 1); \
		echo "✓ Created .env file. Please edit it with your configuration."; \
		echo "  IMPORTANT: Set JWT_SECRET to a random value!"; \
		echo "  Run: make secret"; \
	fi
	@if [ ! -f web/certs/server.crt ] || [ ! -f web/certs/server.key ]; then \
		echo "Generating self-signed TLS certificates..."; \
		mkdir -p web/certs; \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
			-keyout web/certs/server.key \
			-out web/certs/server.crt \
			-subj "/CN=localhost" 2>/dev/null || (echo "ERROR: OpenSSL not found. Install openssl package." && exit 1); \
		chmod 600 web/certs/server.key; \
		chmod 644 web/certs/server.crt; \
		echo "✓ Certificates generated in web/certs/"; \
		echo ""; \
		echo "Note: If running in Docker, the backend container runs as UID 1000 (storagesage)."; \
		echo "If you encounter permission errors, ensure certs are readable by UID 1000:"; \
		echo "  sudo chown 1000:1000 web/certs/server.* (or use your local UID if it matches)"; \
	fi
	@if [ ! -f web/config/config.yaml ]; then \
		echo "Creating default config from example..."; \
		mkdir -p web/config; \
		cp web/config/config.yaml.example web/config/config.yaml 2>/dev/null || true; \
		echo "✓ Created web/config/config.yaml"; \
	fi
	@echo ""
	@echo "✓ Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Edit .env and set JWT_SECRET (required)"
	@echo "  2. Review web/config/config.yaml"
	@echo "  3. Run: make build"
	@echo "  4. Run: make up"

secret: ## Generate a secure JWT secret
	@openssl rand -base64 32

setup-permissions: ## Configure filesystem permissions for non-root container
	@./scripts/setup-permissions.sh

validate-env: ## Validate required environment variables
	@test -f .env || (echo "ERROR: .env not found" && exit 1)
	@test -n "$(JWT_SECRET)" || (echo "ERROR: JWT_SECRET not set" && exit 1)
	@echo "✓ Environment validated"

verify: ## Verify environment setup
	@echo "Verifying environment..."
	@test -f .env || (echo "ERROR: .env file not found. Run 'make setup' first." && exit 1)
	@test -f web/certs/server.crt || (echo "WARNING: TLS certificate not found. Run 'make setup' to generate." && exit 1)
	@test -f web/certs/server.key || (echo "WARNING: TLS key not found. Run 'make setup' to generate." && exit 1)
	@test -f web/config/config.yaml || (echo "WARNING: Config file not found. Run 'make setup' to create." && exit 1)
	@test -n "$(JWT_SECRET)" || (echo "WARNING: JWT_SECRET not set in .env" && exit 1)
	@echo "✓ Environment verified"

generate-override: ## Generate docker-compose.override.yml based on .env
	@./scripts/generate-compose-override.sh

build-docker: validate-env ## Build all Docker containers (includes frontend build in multi-stage)
	@echo "Building Docker containers (multi-stage builds include frontend)..."
	docker compose build

up: validate-env generate-override setup-permissions ## Start all services
	docker compose up -d
	@echo ""
	@echo "✓ StorageSage is running"
	@echo "  Backend:    https://localhost:$(BACKEND_PORT:-8443)"
	@echo "  Frontend:   https://localhost:$(BACKEND_PORT:-8443)"
	@echo ""
	@echo "Verify: docker compose exec storage-sage-backend id"

start: setup build-docker up ## Complete setup and start (production-ready single command)
	@echo ""
	@echo "✓ StorageSage started successfully!"
	@echo ""
	@echo "Access:"
	@echo "  Backend API:  https://localhost:$(BACKEND_PORT:-8443)"
	@echo "  Frontend UI:   https://localhost:$(BACKEND_PORT:-8443)"
	@echo ""
	@echo "Check status: make ps"
	@echo "View logs:    make logs"
	@echo "Health check: make health"

dev-frontend: build-frontend ## Build frontend for local development
	@echo "✓ Frontend ready for local development"
	@echo "  Run backend with: cd web/backend && go run ."
	@echo "  Or use: make start"

down: ## Stop all services
	docker compose down --remove-orphans

restart: down up ## Restart all services

logs: ## Show logs from all services
	docker compose logs -f

logs-backend: ## Show backend logs
	docker compose logs -f storage-sage-backend

ps: ## Show running containers
	docker compose ps

shell-backend: ## Open shell in backend container
	docker compose exec storage-sage-backend sh

clean: down ## Stop and remove volumes
	docker compose down -v

health: ## Check service health status
	@echo "Service Health Status:"
	@docker compose ps
	@echo ""
	@echo "Health Check Details:"
	@docker inspect --format='{{.Name}}: {{.State.Health.Status}}' $$(docker ps -q --filter "name=storage-sage") 2>/dev/null || echo "No health checks available"

health-check: ## Run health checks on all services
	@echo "Running health checks..."
	@echo ""
	@echo "Checking backend..."
	@curl -k -s https://localhost:$(BACKEND_PORT:-8443)/api/v1/health 2>/dev/null | head -1 || echo "✗ Backend health check failed"
	@echo ""
	@echo "Checking daemon metrics..."
	@curl -s http://localhost:$(DAEMON_METRICS_PORT:-9090)/metrics 2>/dev/null | head -5 || echo "✗ Daemon metrics check failed"
	@echo ""
	@echo "Health checks complete"

verify-security: ## Verify non-root execution
	@echo "Backend user:"
	@docker compose exec storage-sage-backend id
	@echo ""
	@echo "Expected: uid=1000(storagesage)"

rollback: ## Rollback to previous version (Usage: make rollback VERSION=v1.0.0)
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: VERSION not specified"; \
		echo "Usage: make rollback VERSION=v1.0.0"; \
		exit 1; \
	fi
	@echo "Rolling back to version $(VERSION)..."
	@docker compose down
	@echo "✓ Rollback complete. Start with: make up"
	@echo "  Note: Update image tag in docker-compose.yml to $(VERSION) before running 'make up'"
