#!/bin/bash
# Install StorageSage systemd services
# Run as root: sudo ./scripts/install-systemd.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

# Check root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    echo "Run: sudo $0"
    exit 1
fi

echo "Installing StorageSage systemd services..."
echo ""

# Create storage-sage user if doesn't exist
if ! id -u storage-sage &>/dev/null; then
    log_info "Creating storage-sage user..."
    useradd --system --no-create-home --shell /bin/false storage-sage
    log_success "User created"
else
    log_info "User storage-sage already exists"
fi

# Create required directories
log_info "Creating directories..."
mkdir -p /opt/storage-sage
mkdir -p /etc/storage-sage
mkdir -p /var/log/storage-sage
mkdir -p /var/lib/storage-sage

# Copy binaries
log_info "Installing binaries..."
if [ ! -d "${PROJECT_ROOT}/build" ]; then
    log_error "Build directory not found. Run ./scripts/build-all.sh first"
    exit 1
fi

cp -r "${PROJECT_ROOT}/build" /opt/storage-sage/
cp -r "${PROJECT_ROOT}/web" /opt/storage-sage/

# Copy config if doesn't exist
if [ ! -f /etc/storage-sage/config.yaml ]; then
    log_info "Installing default config..."
    if [ -f "${PROJECT_ROOT}/web/config/config.yaml" ]; then
        cp "${PROJECT_ROOT}/web/config/config.yaml" /etc/storage-sage/
    else
        log_warn "No config found, you'll need to create /etc/storage-sage/config.yaml"
    fi
fi

# Generate JWT secret if doesn't exist
if [ ! -f /etc/storage-sage/jwt-secret ]; then
    log_info "Generating JWT secret..."
    openssl rand -base64 32 > /etc/storage-sage/jwt-secret
    chmod 600 /etc/storage-sage/jwt-secret
    log_success "JWT secret generated"
fi

# Set permissions
log_info "Setting permissions..."
chown -R storage-sage:storage-sage /opt/storage-sage
chown -R storage-sage:storage-sage /var/log/storage-sage
chown -R storage-sage:storage-sage /var/lib/storage-sage
chown -R storage-sage:storage-sage /etc/storage-sage
chmod 750 /opt/storage-sage/build/storage-sage
chmod 750 /opt/storage-sage/build/storage-sage-web

# Install service files
log_info "Installing systemd service files..."
cp "${PROJECT_ROOT}/storage-sage-daemon.service" /etc/systemd/system/
cp "${PROJECT_ROOT}/storage-sage-backend.service" /etc/systemd/system/

# Reload systemd
log_info "Reloading systemd..."
systemctl daemon-reload

echo ""
log_success "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Review/edit config: /etc/storage-sage/config.yaml"
echo "  2. Enable services:"
echo "     sudo systemctl enable storage-sage-daemon"
echo "     sudo systemctl enable storage-sage-backend"
echo "  3. Start services:"
echo "     sudo systemctl start storage-sage-daemon"
echo "     sudo systemctl start storage-sage-backend"
echo "  4. Check status:"
echo "     sudo systemctl status storage-sage-daemon"
echo "     sudo systemctl status storage-sage-backend"
echo ""
