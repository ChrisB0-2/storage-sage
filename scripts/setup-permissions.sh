#!/bin/bash
set -euo pipefail

# setup-permissions.sh
# Configures host filesystem permissions for non-root container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

STORAGESAGE_UID=1000
STORAGESAGE_GID=1000

echo "========================================="
echo "StorageSage Permission Setup"
echo "========================================="
echo ""
echo "Container runs as UID:GID ${STORAGESAGE_UID}:${STORAGESAGE_GID}"
echo "Project root: $PROJECT_ROOT"
echo ""

# Create directories if they don't exist
echo "Creating required directories..."
mkdir -p "$PROJECT_ROOT/logs"
mkdir -p "$PROJECT_ROOT/config"
mkdir -p "$PROJECT_ROOT/data"

# Set ownership
echo "Setting ownership to ${STORAGESAGE_UID}:${STORAGESAGE_GID}..."
sudo chown -R ${STORAGESAGE_UID}:${STORAGESAGE_GID} \
    "$PROJECT_ROOT/logs" \
    "$PROJECT_ROOT/config" \
    "$PROJECT_ROOT/data" 2>/dev/null || {
    echo "⚠️  Warning: Could not set ownership (may need sudo)"
    echo "   Run manually: sudo chown -R ${STORAGESAGE_UID}:${STORAGESAGE_GID} logs config data"
}

# Set permissions
chmod -R 755 "$PROJECT_ROOT/logs" 2>/dev/null || true
chmod -R 755 "$PROJECT_ROOT/config" 2>/dev/null || true
chmod -R 755 "$PROJECT_ROOT/data" 2>/dev/null || true

echo "✓ Local directories configured"
echo ""

# Check NFS mount permissions
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    echo "Checking scan path permissions..."
    source "$PROJECT_ROOT/.env"
    
    check_path() {
        local path="$1"
        local name="$2"
        
        if [[ -z "$path" ]]; then
            echo "  ℹ️  $name not configured"
            return
        fi
        
        if [[ ! -d "$path" ]]; then
            echo "  ⚠️  $name does not exist: $path"
            return
        fi
        
        echo "  Checking $name: $path"
        
        # Test read permission
        if sudo -u "#${STORAGESAGE_UID}" test -r "$path" 2>/dev/null; then
            echo "    ✓ Readable by UID ${STORAGESAGE_UID}"
        else
            echo "    ✗ NOT readable by UID ${STORAGESAGE_UID}"
            echo "      Fix: sudo chown -R ${STORAGESAGE_UID}:${STORAGESAGE_GID} $path"
        fi
        
        # Test write permission
        if sudo -u "#${STORAGESAGE_UID}" test -w "$path" 2>/dev/null; then
            echo "    ✓ Writable by UID ${STORAGESAGE_UID}"
        else
            echo "    ✗ NOT writable by UID ${STORAGESAGE_UID}"
            echo "      Container won't be able to delete files"
            echo "      Fix: sudo chown -R ${STORAGESAGE_UID}:${STORAGESAGE_GID} $path"
        fi
    }
    
    check_path "${SCAN_PATH_1:-}" "SCAN_PATH_1"
    check_path "${SCAN_PATH_2:-}" "SCAN_PATH_2"
    check_path "${NFS_MOUNT_PATH:-}" "NFS_MOUNT_PATH"
else
    echo "⚠️  .env file not found - skipping scan path checks"
    echo "   Create .env first: cp .env.example .env"
fi

echo ""
echo "========================================="
echo "Setup Complete"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Review any warnings above"
echo "  2. Run: make build"
echo "  3. Run: make up"
echo "  4. Verify: docker compose exec backend id"
echo ""
