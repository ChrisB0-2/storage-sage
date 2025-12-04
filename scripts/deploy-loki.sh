#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Deploying StorageSage Loki Integration..."

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed"
    exit 1
fi

# Check if config files exist
if [[ ! -f "$PROJECT_ROOT/promtail-config.yml" ]]; then
    echo "❌ promtail-config.yml not found"
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/loki-config.yml" ]]; then
    echo "❌ loki-config.yml not found"
    exit 1
fi

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p "$PROJECT_ROOT/grafana/provisioning/datasources"
mkdir -p "$PROJECT_ROOT/grafana/dashboards"

# Start services
echo "🐳 Starting Loki stack..."
cd "$PROJECT_ROOT"

if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

$DOCKER_COMPOSE up -d loki promtail

# Wait for services to be healthy
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check Loki health
if curl -f http://localhost:3100/ready &> /dev/null; then
    echo "✅ Loki is ready"
else
    echo "⚠️  Loki health check failed, but continuing..."
fi

# Check Promtail health
if curl -f http://localhost:9080/ready &> /dev/null; then
    echo "✅ Promtail is ready"
else
    echo "⚠️  Promtail health check failed, but continuing..."
fi

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Access Grafana at: http://localhost:3001"
echo "🔍 Loki API at: http://localhost:3100"
echo ""
echo "To view logs:"
echo "  docker logs storage-sage-loki"
echo "  docker logs storage-sage-promtail"

