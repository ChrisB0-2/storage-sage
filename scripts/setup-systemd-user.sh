#!/bin/bash
#
# StorageSage SystemD User Setup Script
# Creates the storage-sage system user and sets up proper permissions
#
# Usage: sudo ./scripts/setup-systemd-user.sh
#

set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "StorageSage SystemD User Setup"
echo "==============================="
echo ""

# Create storage-sage system user and group
echo "Creating storage-sage system user and group..."
if ! id -u storage-sage >/dev/null 2>&1; then
    useradd --system \
        --no-create-home \
        --shell /usr/sbin/nologin \
        --comment "StorageSage Cleanup Daemon" \
        storage-sage
    echo "✓ Created storage-sage user"
else
    echo "✓ storage-sage user already exists"
fi

# Create required directories
echo ""
echo "Creating required directories..."
mkdir -p /etc/storage-sage
mkdir -p /var/log/storage-sage
mkdir -p /var/lib/storage-sage

# Set ownership and permissions
echo "Setting ownership and permissions..."
chown -R storage-sage:storage-sage /etc/storage-sage
chown -R storage-sage:storage-sage /var/log/storage-sage
chown -R storage-sage:storage-sage /var/lib/storage-sage

chmod 755 /etc/storage-sage
chmod 750 /var/log/storage-sage
chmod 750 /var/lib/storage-sage

echo "✓ Directories created and permissions set"

# Install systemd service file if it exists
echo ""
if [ -f "storage-sage.service" ]; then
    echo "Installing SystemD service file..."
    cp storage-sage.service /etc/systemd/system/storage-sage.service
    chmod 644 /etc/systemd/system/storage-sage.service
    systemctl daemon-reload
    echo "✓ SystemD service installed"
    echo ""
    echo "To enable and start the service:"
    echo "  systemctl enable storage-sage"
    echo "  systemctl start storage-sage"
elif [ -f "cmd/storage-sage/storage-sage.service" ]; then
    echo "Installing SystemD service file..."
    cp cmd/storage-sage/storage-sage.service /etc/systemd/system/storage-sage.service
    chmod 644 /etc/systemd/system/storage-sage.service
    systemctl daemon-reload
    echo "✓ SystemD service installed"
    echo ""
    echo "To enable and start the service:"
    echo "  systemctl enable storage-sage"
    echo "  systemctl start storage-sage"
else
    echo "⚠ SystemD service file not found in current directory"
    echo "  Copy it manually to /etc/systemd/system/"
fi

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Copy your storage-sage binary to /usr/local/bin/storage-sage"
echo "  2. Copy your config.yaml to /etc/storage-sage/config.yaml"
echo "  3. Adjust file permissions on scan paths if needed"
echo "  4. Enable and start the service:"
echo "       systemctl enable storage-sage"
echo "       systemctl start storage-sage"
echo "  5. Check status:"
echo "       systemctl status storage-sage"
echo "       journalctl -u storage-sage -f"
