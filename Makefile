.PHONY: help build up down logs clean test generate-override setup-permissions validate-env setup start health secret verify

.DEFAULT_GOAL := help

-include .env
export

help: ## Show this help message
	@echo "StorageSage Docker Management"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

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

build: validate-env ## Build all containers
	docker compose build

up: validate-env generate-override setup-permissions ## Start all services
	docker compose up -d
	@echo ""
	@echo "✓ StorageSage is running"
	@echo "  Backend:    https://localhost:$(BACKEND_PORT:-8443)"
	@echo "  Frontend:   https://localhost:$(BACKEND_PORT:-8443)"
	@echo ""
	@echo "Verify: docker compose exec storage-sage-backend id"

start: setup build up ## Complete setup and start (production-ready single command)
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

test: ## Run health checks on all services
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
