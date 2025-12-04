#!/bin/bash
# Start all StorageSage services
# Usage: ./start-all.sh [--with-grafana]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

WITH_GRAFANA=false
if [[ "${1:-}" == "--with-grafana" ]]; then
    WITH_GRAFANA=true
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Starting StorageSage${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker not found${NC}"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}ERROR: Docker daemon not running${NC}"
    exit 1
fi

# Check if already running
if docker compose ps | grep -q "Up"; then
    echo -e "${YELLOW}⚠ Some services are already running${NC}"
    echo "Stopping existing services..."
    docker compose down
    echo ""
fi

# Run setup if needed (creates .env, certs, config)
echo -e "${GREEN}[1/4]${NC} Checking prerequisites..."
if [ ! -f .env ] || [ ! -f web/certs/server.crt ] || [ ! -f web/config/config.yaml ]; then
    echo "Running setup..."
    make setup || {
        echo -e "${RED}Setup failed. Please check errors above.${NC}"
        exit 1
    }
else
    echo "✓ Prerequisites OK"
fi
echo ""

# Build images
echo -e "${GREEN}[2/4]${NC} Building Docker images..."
docker compose build
echo ""

# Generate override and setup permissions
echo -e "${GREEN}[3/4]${NC} Preparing configuration..."
make generate-override setup-permissions 2>/dev/null || true
echo ""

# Start services
echo -e "${GREEN}[4/4]${NC} Starting services..."
docker compose up -d

# Start Grafana if requested
if [ "$WITH_GRAFANA" = true ]; then
    echo "Starting Grafana..."
    docker compose --profile grafana up -d grafana
fi

# Wait for services to initialize
echo ""
echo "Waiting for services to initialize (15 seconds)..."
sleep 15

# Show status
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ StorageSage Started!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Services:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "Access Points:"
echo "  • Frontend/UI:  https://localhost:8443"
echo "  • Backend API:  https://localhost:8443/api/v1"
echo "  • Daemon Metrics: http://localhost:9090/metrics"
echo "  • Loki:         http://localhost:3100"
if [ "$WITH_GRAFANA" = true ]; then
    echo "  • Grafana:      http://localhost:3001"
fi
echo ""
echo "Useful Commands:"
echo "  View logs:    docker compose logs -f"
echo "  Stop all:     docker compose down"
echo "  Check status: docker compose ps"
echo "  Health check: make health"
echo ""
