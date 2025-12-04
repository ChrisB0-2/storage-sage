#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups/loki}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "💾 Backing up Loki data..."

mkdir -p "$BACKUP_DIR"

# Backup Loki data volume
if docker volume inspect storage-sage-loki-data &> /dev/null; then
    echo "Backing up loki-data volume..."
    docker run --rm \
        -v storage-sage-loki-data:/data \
        -v "$BACKUP_DIR:/backup" \
        alpine tar czf "/backup/loki-data-${TIMESTAMP}.tar.gz" -C /data .
    echo "✅ Loki data backed up to: $BACKUP_DIR/loki-data-${TIMESTAMP}.tar.gz"
else
    echo "⚠️  Loki data volume not found"
fi

# Backup configurations
echo "Backing up configurations..."
tar czf "$BACKUP_DIR/loki-configs-${TIMESTAMP}.tar.gz" \
    -C "$PROJECT_ROOT" \
    promtail-config.yml \
    loki-config.yml \
    storage-sage-alerts.yml \
    grafana/provisioning/datasources \
    grafana/dashboards 2>/dev/null || true

echo "✅ Configurations backed up"
echo ""
echo "Backup location: $BACKUP_DIR"
echo "Total size: $(du -sh "$BACKUP_DIR" | cut -f1)"

