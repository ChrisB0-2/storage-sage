#!/bin/bash
# StorageSage Complete Startup Script
# Builds frontend and starts all Docker services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  StorageSage Complete Startup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

cd "$PROJECT_ROOT"

# Step 1: Build Frontend
log_info "Building frontend..."
cd web/frontend

# Check if .env exists
if [ ! -f ".env" ]; then
    log_warn ".env not found, creating with default values..."
    echo "VITE_API_URL=https://localhost:8443/api/v1" > .env
    log_success "Created .env file"
fi

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    log_info "node_modules not found, running npm install..."
    if ! npm install; then
        log_error "npm install failed"
        exit 1
    fi
    log_success "npm install completed"
fi

# Build frontend
log_info "Running npm build..."
if ! npm run build; then
    log_error "Frontend build failed"
    exit 1
fi

# Verify dist directory was created
if [ ! -d "dist" ]; then
    log_error "dist directory not found after build"
    exit 1
fi

cd "$PROJECT_ROOT"
log_success "Frontend built successfully: web/frontend/dist/"
echo ""

# Step 2: Start Docker containers
log_info "Starting Docker containers..."

# Check if containers are already running
if docker ps --filter "name=storage-sage" --format "{{.Names}}" | grep -q storage-sage; then
    log_warn "Storage-Sage containers already running, restarting..."
    docker restart storage-sage-daemon storage-sage-backend
    log_success "Containers restarted"
else
    log_info "Starting containers with docker-compose..."
    docker-compose up -d storage-sage-daemon storage-sage-backend loki promtail
    log_success "Containers started"
fi

echo ""
log_info "Waiting for services to be ready..."
sleep 5

# Step 3: Verify services
log_info "Verifying service health..."

errors=0

# Check daemon
if docker ps --filter "name=storage-sage-daemon" --filter "status=running" --format "{{.Names}}" | grep -q storage-sage-daemon; then
    log_success "✓ Daemon is running"
else
    log_error "✗ Daemon is not running"
    errors=$((errors + 1))
fi

# Check backend
if docker ps --filter "name=storage-sage-backend" --filter "status=running" --format "{{.Names}}" | grep -q storage-sage-backend; then
    log_success "✓ Backend is running"
else
    log_error "✗ Backend is not running"
    errors=$((errors + 1))
fi

# Check if backend is responding
if curl -sk https://localhost:8443/api/v1/health > /dev/null 2>&1; then
    log_success "✓ Backend API is responding"
else
    log_warn "⚠ Backend API not responding yet (may still be starting)"
fi

echo ""

if [ $errors -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  StorageSage Started Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}Access Points:${NC}"
    echo -e "  Web UI:          ${BLUE}https://localhost:8443${NC}"
    echo -e "  Backend API:     ${BLUE}https://localhost:8443/api/v1${NC}"
    echo -e "  Daemon Metrics:  ${BLUE}http://localhost:9090/metrics${NC}"
    echo ""
    echo -e "${YELLOW}Default Credentials:${NC}"
    echo -e "  Username: ${BLUE}admin${NC}"
    echo -e "  Password: ${BLUE}changeme${NC}"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  View logs:       ${BLUE}docker-compose logs -f${NC}"
    echo -e "  Stop services:   ${BLUE}./scripts/stop-all.sh${NC}"
    echo -e "  Restart backend: ${BLUE}docker restart storage-sage-backend${NC}"
    echo ""
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  Startup completed with errors${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Check logs with:${NC} docker-compose logs"
    exit 1
fi
