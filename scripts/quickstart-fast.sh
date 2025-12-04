#!/bin/bash
# StorageSage Fast Start - Skip frontend build, use Docker only

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

echo -e "${CYAN}"
echo "========================================"
echo "  StorageSage Fast Start"
echo "========================================"
echo -e "${NC}"

cd "${PROJECT_ROOT}"

# Step 1: Generate JWT secret (fast)
log_info "Setting up JWT secret..."
mkdir -p secrets
if [ ! -f secrets/jwt_secret.txt ]; then
    openssl rand -base64 32 > secrets/jwt_secret.txt
    chmod 600 secrets/jwt_secret.txt
fi
log_success "JWT secret ready"

# Step 2: Create .env if missing (fast)
log_info "Checking .env..."
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        log_warn "Created .env - review settings if needed"
    else
        log_error ".env.example missing!"
        exit 1
    fi
fi
log_success ".env ready"

# Step 3: Generate TLS certs (fast)
log_info "Setting up TLS certificates..."
mkdir -p web/certs
if [ ! -f web/certs/server.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout web/certs/server.key \
        -out web/certs/server.crt \
        -subj "/CN=localhost" 2>/dev/null
    chmod 600 web/certs/server.key
fi
log_success "TLS certificates ready"

# Step 4: Create config if missing (fast)
log_info "Checking config..."
mkdir -p web/config
if [ ! -f web/config/config.yaml ]; then
    if [ -f test-config.yaml ]; then
        cp test-config.yaml web/config/config.yaml
        log_success "Config created from test-config.yaml"
    else
        cat > web/config/config.yaml <<'EOF'
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
        log_success "Config created"
    fi
fi

# Step 5: Start with Docker (Docker will build if needed)
log_info "Starting services with Docker Compose..."
log_warn "First-time build may take 2-5 minutes..."

# Generate override if script exists
if [ -f scripts/generate-compose-override.sh ]; then
    bash scripts/generate-compose-override.sh 2>/dev/null || true
fi

# Start services (Docker will build containers automatically)
docker compose up -d

log_success "Services starting..."

# Step 6: Wait and check
log_info "Waiting 15 seconds for services to initialize..."
sleep 15

# Source .env for ports
set -a
source .env 2>/dev/null || true
set +a

BACKEND_PORT="${BACKEND_PORT:-8443}"
DAEMON_METRICS_PORT="${DAEMON_METRICS_PORT:-9090}"

echo ""
echo -e "${GREEN}✓ StorageSage started!${NC}"
echo ""
echo -e "${CYAN}Access:${NC}"
echo -e "  • Web UI:     ${GREEN}https://localhost:${BACKEND_PORT}${NC}"
echo -e "  • Metrics:    ${GREEN}http://localhost:${DAEMON_METRICS_PORT}/metrics${NC}"
echo ""
echo -e "${CYAN}Login:${NC}"
echo -e "  • User: ${YELLOW}admin${NC}"
echo -e "  • Pass: ${YELLOW}changeme${NC}"
echo ""
echo -e "${CYAN}Status:${NC}"

# Quick health check
if curl -k -s -f "https://localhost:${BACKEND_PORT}/api/v1/health" >/dev/null 2>&1; then
    echo -e "  • Backend: ${GREEN}✓ Healthy${NC}"
else
    echo -e "  • Backend: ${YELLOW}⧗ Starting...${NC}"
fi

if curl -s -f "http://localhost:${DAEMON_METRICS_PORT}/metrics" >/dev/null 2>&1; then
    echo -e "  • Daemon:  ${GREEN}✓ Healthy${NC}"
else
    echo -e "  • Daemon:  ${YELLOW}⧗ Starting...${NC}"
fi

echo ""
echo -e "${CYAN}Commands:${NC}"
echo -e "  • Logs:   ${BLUE}docker compose logs -f${NC}"
echo -e "  • Stop:   ${BLUE}docker compose down${NC}"
echo -e "  • Status: ${BLUE}docker compose ps${NC}"
echo ""
