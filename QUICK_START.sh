#!/bin/bash
# StorageSage Quick Start Script
# This script provides a fast path to deployment with minimal interaction
#
# Usage: ./QUICK_START.sh

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  StorageSage Quick Start${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Verify we're in the right directory
echo -e "${GREEN}[1/8]${NC} Verifying working directory..."
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}ERROR: docker-compose.yml not found${NC}"
    echo "Please run this script from the storage-sage project root"
    exit 1
fi
echo "✓ Working directory confirmed: $(pwd)"
echo ""

# Step 2: Check Docker
echo -e "${GREEN}[2/8]${NC} Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker not found${NC}"
    echo "Please install Docker and try again"
    exit 1
fi
if ! docker ps &> /dev/null; then
    echo -e "${RED}ERROR: Docker daemon not running${NC}"
    echo "Please start Docker and try again"
    exit 1
fi
DOCKER_VERSION=$(docker --version)
COMPOSE_VERSION=$(docker compose version)
echo "✓ Docker detected: $DOCKER_VERSION"
echo "✓ Docker Compose detected: $COMPOSE_VERSION"
echo ""

# Step 3: Verify prerequisites
echo -e "${GREEN}[3/8]${NC} Verifying prerequisites..."
MISSING=0

if [ ! -f "web/certs/server.crt" ] || [ ! -f "web/certs/server.key" ]; then
    echo -e "${YELLOW}⚠ TLS certificates missing${NC}"
    MISSING=1
fi

if [ ! -f "secrets/jwt_secret.txt" ]; then
    echo -e "${YELLOW}⚠ JWT secret missing${NC}"
    MISSING=1
fi

if [ ! -f "web/config/config.yaml" ]; then
    echo -e "${YELLOW}⚠ Configuration file missing${NC}"
    MISSING=1
fi

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "Running setup to create missing files..."
    make setup
fi

echo "✓ All prerequisites verified"
echo ""

# Step 4: Create test workspace
echo -e "${GREEN}[4/8]${NC} Creating test workspace..."
mkdir -p /tmp/storage-sage-test-workspace
echo "Test file for age-based deletion" > /tmp/storage-sage-test-workspace/test-file.txt
touch -d "2 days ago" /tmp/storage-sage-test-workspace/test-file.txt
echo "✓ Test workspace created at /tmp/storage-sage-test-workspace"
echo ""

# Step 5: Build images
echo -e "${GREEN}[5/8]${NC} Building Docker images (this may take 10-15 minutes)..."
docker compose build --no-cache
echo "✓ Images built successfully"
echo ""

# Step 6: Start services
echo -e "${GREEN}[6/8]${NC} Starting services..."
docker compose up -d
echo "✓ Services started"
echo ""

# Step 7: Wait for services to initialize
echo -e "${GREEN}[7/8]${NC} Waiting for services to initialize (30 seconds)..."
sleep 30
echo "✓ Initialization complete"
echo ""

# Step 8: Health checks
echo -e "${GREEN}[8/8]${NC} Running health checks..."
HEALTH_OK=1

echo -n "  Checking daemon... "
if curl -sf http://localhost:9090/metrics > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    HEALTH_OK=0
fi

echo -n "  Checking backend... "
if curl -sk https://localhost:8443/api/v1/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    HEALTH_OK=0
fi

echo -n "  Checking Loki... "
if docker ps --format '{{.Names}}' | grep -q 'storage-sage-loki'; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⊘${NC} (not required)"
fi

echo -n "  Checking Promtail... "
if docker ps --format '{{.Names}}' | grep -q 'storage-sage-promtail'; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⊘${NC} (not required)"
fi

echo ""

if [ $HEALTH_OK -eq 1 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ✓ StorageSage is running!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Access Points:"
    echo "  • Backend API:  https://localhost:8443"
    echo "  • Frontend UI:  https://localhost:8443"
    echo "  • Metrics:      http://localhost:9090/metrics"
    echo ""
    echo "Default Credentials:"
    echo "  Username: admin"
    echo "  Password: changeme"
    echo ""
    echo "Next Steps:"
    echo "  1. Open browser to https://localhost:8443"
    echo "  2. Run tests: ./scripts/comprehensive_test.sh"
    echo "  3. View logs: docker compose logs -f"
    echo "  4. Read manual: cat DEPLOYMENT_MANUAL.md"
    echo ""
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  ⚠ Some health checks failed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check logs: docker compose logs"
    echo "  2. Check status: docker compose ps"
    echo "  3. Restart: docker compose restart"
    echo "  4. Review: cat DEPLOYMENT_MANUAL.md"
    echo ""
    exit 1
fi
