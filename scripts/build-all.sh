#!/bin/bash
# StorageSage Unified Build Script
# Builds: daemon, backend, and frontend in one command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color codes
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

echo -e "${GREEN}========================================"
echo "  StorageSage Unified Build"
echo "========================================${NC}"
echo ""

cd "$PROJECT_ROOT"

# Step 1: Build Go Daemon
log_info "Building Go daemon (storage-sage)..."
mkdir -p build
if ! go build -o build/storage-sage ./cmd/storage-sage; then
    log_error "Failed to build daemon"
    exit 1
fi
log_success "Daemon built: build/storage-sage"
echo ""

# Step 2: Build Go Backend (Web API)
log_info "Building Go backend (storage-sage-web)..."
cd web/backend
if ! go build -o ../../build/storage-sage-web .; then
    cd "$PROJECT_ROOT"
    log_error "Failed to build backend"
    exit 1
fi
cd "$PROJECT_ROOT"
log_success "Backend built: build/storage-sage-web"
echo ""

# Step 3: Build Frontend-v2 (CoreUI React/Vite)
log_info "Building frontend-v2 (CoreUI React app)..."
cd web/frontend-v2

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    log_warn "node_modules not found, running npm install..."
    if ! npm install; then
        log_error "npm install failed"
        exit 1
    fi
fi

# Build frontend
if ! npm run build; then
    log_error "Frontend build failed"
    exit 1
fi

cd "$PROJECT_ROOT"
log_success "Frontend built: web/frontend-v2/dist/"
echo ""

# Step 4: Verify build outputs
log_info "Verifying build artifacts..."
errors=0

if [ ! -f "build/storage-sage" ]; then
    log_error "Daemon binary not found"
    errors=$((errors + 1))
else
    log_success "✓ build/storage-sage"
fi

if [ ! -f "build/storage-sage-web" ]; then
    log_error "Backend binary not found"
    errors=$((errors + 1))
else
    log_success "✓ build/storage-sage-web"
fi

if [ ! -d "web/frontend-v2/dist" ] || [ ! -f "web/frontend-v2/dist/index.html" ]; then
    log_error "Frontend build output not found"
    errors=$((errors + 1))
else
    log_success "✓ web/frontend-v2/dist/index.html"
fi

echo ""

if [ $errors -gt 0 ]; then
    log_error "Build completed with $errors error(s)"
    exit 1
fi

log_success "All components built successfully!"
echo ""
echo "Build artifacts:"
echo "  Daemon:   build/storage-sage"
echo "  Backend:  build/storage-sage-web"
echo "  Frontend: web/frontend-v2/dist/"
echo ""
echo "Next: Run ./scripts/start-all.sh to start the system"
