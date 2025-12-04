#!/bin/bash
# StorageSage Quick Start - Complete Setup and Launch
# Handles: initial setup, builds, and startup in one command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

show_banner() {
    echo -e "${CYAN}"
    echo "========================================"
    echo "  StorageSage QuickStart"
    echo "  Complete Setup & Launch"
    echo "========================================"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v docker-compose >/dev/null 2>&1 || command -v docker compose >/dev/null 2>&1 || missing+=("docker-compose")
    command -v openssl >/dev/null 2>&1 || missing+=("openssl")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Please install: ${missing[*]}"
        exit 1
    fi

    log_success "Prerequisites OK"
}

# Generate .env if missing
setup_env() {
    if [ ! -f "${PROJECT_ROOT}/.env" ]; then
        log_info "Creating .env file..."

        if [ -f "${PROJECT_ROOT}/.env.example" ]; then
            cp "${PROJECT_ROOT}/.env.example" "${PROJECT_ROOT}/.env"
            log_success "Created .env from .env.example"
            log_warn "IMPORTANT: Edit .env and set JWT_SECRET before production use!"
            log_warn "Generate secret with: openssl rand -base64 32"
        else
            log_error ".env.example not found!"
            exit 1
        fi
    else
        log_success ".env file exists"
    fi
}

# Generate JWT secret if missing
setup_jwt_secret() {
    mkdir -p "${PROJECT_ROOT}/secrets"

    if [ ! -f "${PROJECT_ROOT}/secrets/jwt_secret.txt" ]; then
        log_info "Generating JWT secret..."
        openssl rand -base64 32 > "${PROJECT_ROOT}/secrets/jwt_secret.txt"
        chmod 600 "${PROJECT_ROOT}/secrets/jwt_secret.txt"
        log_success "JWT secret generated"
    else
        log_success "JWT secret exists"
    fi
}

# Generate TLS certificates if missing
setup_tls() {
    mkdir -p "${PROJECT_ROOT}/web/certs"

    if [ ! -f "${PROJECT_ROOT}/web/certs/server.crt" ] || [ ! -f "${PROJECT_ROOT}/web/certs/server.key" ]; then
        log_info "Generating self-signed TLS certificates..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${PROJECT_ROOT}/web/certs/server.key" \
            -out "${PROJECT_ROOT}/web/certs/server.crt" \
            -subj "/CN=localhost" 2>/dev/null
        chmod 600 "${PROJECT_ROOT}/web/certs/server.key"
        chmod 644 "${PROJECT_ROOT}/web/certs/server.crt"
        log_success "TLS certificates generated"
    else
        log_success "TLS certificates exist"
    fi
}

# Setup config if missing
setup_config() {
    mkdir -p "${PROJECT_ROOT}/web/config"

    if [ ! -f "${PROJECT_ROOT}/web/config/config.yaml" ]; then
        log_info "Creating default config..."

        if [ -f "${PROJECT_ROOT}/web/config/config.yaml.example" ]; then
            cp "${PROJECT_ROOT}/web/config/config.yaml.example" "${PROJECT_ROOT}/web/config/config.yaml"
        else
            # Create minimal config if example doesn't exist
            cat > "${PROJECT_ROOT}/web/config/config.yaml" <<EOF
scan_paths:
  - /var/log
  - /tmp/storage-sage-test-workspace

min_free_percent: 10
age_off_days: 7
interval_minutes: 15

database_path: /var/lib/storage-sage/deletions.db

prometheus:
  port: 9090

logging:
  rotation_days: 30

resource_limits:
  max_cpu_percent: 10

cleanup_options:
  recursive: true
  delete_dirs: false

nfs_timeout_seconds: 5
EOF
        fi
        log_success "Config created"
    else
        log_success "Config exists"
    fi
}

# Build frontend if needed
build_frontend() {
    if [ -d "${PROJECT_ROOT}/web/frontend" ]; then
        if [ ! -d "${PROJECT_ROOT}/web/frontend/dist" ]; then
            log_info "Building frontend..."
            cd "${PROJECT_ROOT}/web/frontend"

            if [ ! -d "node_modules" ]; then
                log_info "Installing frontend dependencies..."
                npm install
            fi

            log_info "Running frontend build..."
            npm run build

            log_success "Frontend built"
            cd "${PROJECT_ROOT}"
        else
            log_success "Frontend already built"
        fi
    else
        log_warn "Frontend directory not found, skipping frontend build"
    fi
}

# Build Docker containers
build_containers() {
    log_info "Building Docker containers..."
    cd "${PROJECT_ROOT}"

    # Source .env for build-time variables
    set -a
    source .env 2>/dev/null || true
    set +a

    docker compose build
    log_success "Containers built"
}

# Start services
start_services() {
    log_info "Starting services..."
    cd "${PROJECT_ROOT}"

    # Generate override if script exists
    if [ -f "${PROJECT_ROOT}/scripts/generate-compose-override.sh" ]; then
        bash "${PROJECT_ROOT}/scripts/generate-compose-override.sh" 2>/dev/null || true
    fi

    # Setup permissions if script exists
    if [ -f "${PROJECT_ROOT}/scripts/setup-permissions.sh" ]; then
        bash "${PROJECT_ROOT}/scripts/setup-permissions.sh" 2>/dev/null || true
    fi

    docker compose up -d
    log_success "Services started"
}

# Show access information
show_access_info() {
    # Source .env to get ports
    set -a
    source "${PROJECT_ROOT}/.env" 2>/dev/null || true
    set +a

    BACKEND_PORT="${BACKEND_PORT:-8443}"
    DAEMON_METRICS_PORT="${DAEMON_METRICS_PORT:-9090}"
    GRAFANA_PORT="${GRAFANA_PORT:-3001}"
    LOKI_PORT="${LOKI_PORT:-3100}"

    echo ""
    echo -e "${GREEN}✓ StorageSage is running!${NC}"
    echo ""
    echo -e "${CYAN}Access URLs:${NC}"
    echo -e "  • Web UI:        ${GREEN}https://localhost:${BACKEND_PORT}${NC}"
    echo -e "  • Backend API:   ${GREEN}https://localhost:${BACKEND_PORT}/api/v1${NC}"
    echo -e "  • Daemon Metrics: ${GREEN}http://localhost:${DAEMON_METRICS_PORT}/metrics${NC}"
    echo -e "  • Loki:          ${GREEN}http://localhost:${LOKI_PORT}${NC}"
    echo ""
    echo -e "${CYAN}Default Credentials:${NC}"
    echo -e "  • Username: ${YELLOW}admin${NC}"
    echo -e "  • Password: ${YELLOW}changeme${NC}"
    echo -e "  ${RED}⚠ CHANGE THESE IN PRODUCTION!${NC}"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  • View logs:     ${BLUE}docker compose logs -f${NC}"
    echo -e "  • Stop services: ${BLUE}docker compose down${NC}"
    echo -e "  • Check status:  ${BLUE}docker compose ps${NC}"
    echo -e "  • Health check:  ${BLUE}make health${NC}"
    echo ""
}

# Run health checks
run_health_checks() {
    log_info "Running health checks (waiting 10s for services to start)..."
    sleep 10

    # Source .env for ports
    set -a
    source "${PROJECT_ROOT}/.env" 2>/dev/null || true
    set +a

    BACKEND_PORT="${BACKEND_PORT:-8443}"
    DAEMON_METRICS_PORT="${DAEMON_METRICS_PORT:-9090}"

    local checks_passed=0
    local checks_total=2

    # Check backend
    if curl -k -s -f "https://localhost:${BACKEND_PORT}/api/v1/health" >/dev/null 2>&1; then
        log_success "Backend health check passed"
        ((checks_passed++))
    else
        log_warn "Backend health check failed (may still be starting)"
    fi

    # Check daemon metrics
    if curl -s -f "http://localhost:${DAEMON_METRICS_PORT}/metrics" >/dev/null 2>&1; then
        log_success "Daemon metrics check passed"
        ((checks_passed++))
    else
        log_warn "Daemon metrics check failed (may still be starting)"
    fi

    echo ""
    log_info "Health checks: ${checks_passed}/${checks_total} passed"

    if [ $checks_passed -lt $checks_total ]; then
        log_warn "Some health checks failed. Services may still be starting."
        log_info "Check logs with: docker compose logs -f"
    fi
}

# Main execution
main() {
    show_banner

    check_prerequisites
    setup_env
    setup_jwt_secret
    setup_tls
    setup_config
    build_frontend
    build_containers
    start_services
    show_access_info
    run_health_checks

    echo ""
    log_success "QuickStart complete!"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: $0"
            echo ""
            echo "Complete setup and launch of StorageSage"
            echo "Handles: .env, JWT secret, TLS certs, config, build, and startup"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
    shift
done

main
