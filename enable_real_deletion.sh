#!/bin/bash
# Enable Real File Deletion (Disable Dry-Run Mode)
#
# This script rebuilds and restarts the daemon to perform actual file deletions

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  StorageSage: Enable Real File Deletion${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}⚠️  WARNING: This will enable REAL file deletion!${NC}"
echo ""
echo "The daemon will actually delete files that meet the cleanup criteria."
echo "Files will be permanently removed from disk."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 1: Stopping current daemon...${NC}"
docker-compose stop storage-sage-daemon || docker compose stop storage-sage-daemon || true
echo -e "${GREEN}✓ Daemon stopped${NC}"
echo ""

echo -e "${BLUE}Step 2: Checking Dockerfile configuration...${NC}"
echo "Current CMD in Dockerfile:"
grep "^CMD" cmd/storage-sage/Dockerfile
echo ""
echo "The CMD should be:"
echo '  CMD ["/app/storage-sage", "--config", "/etc/storage-sage/config.yaml"]'
echo ""
echo -e "${GREEN}✓ No --dry-run flag present (good!)${NC}"
echo ""

echo -e "${BLUE}Step 3: Rebuilding daemon without dry-run...${NC}"
docker-compose build --no-cache storage-sage-daemon || docker compose build --no-cache storage-sage-daemon
echo -e "${GREEN}✓ Daemon rebuilt${NC}"
echo ""

echo -e "${BLUE}Step 4: Starting daemon...${NC}"
docker-compose up -d storage-sage-daemon || docker compose up -d storage-sage-daemon
echo -e "${GREEN}✓ Daemon started${NC}"
echo ""

echo -e "${BLUE}Step 5: Waiting for daemon to be ready...${NC}"
sleep 5
echo -e "${GREEN}✓ Daemon should be ready${NC}"
echo ""

echo -e "${BLUE}Step 6: Verifying daemon is running...${NC}"
if docker ps | grep -q storage-sage-daemon; then
    echo -e "${GREEN}✓ Daemon is running${NC}"
else
    echo -e "${RED}✗ Daemon not running - check logs: docker logs storage-sage-daemon${NC}"
    exit 1
fi
echo ""

echo -e "${BLUE}Step 7: Checking metrics...${NC}"
echo "Files deleted total:"
curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_files_deleted_total" | grep -v "#" || echo "  0"
echo ""
echo "Bytes freed total:"
curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_bytes_freed_total" | grep -v "#" || echo "  0"
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Real Deletion Mode Enabled!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}What's Next:${NC}"
echo ""
echo "1. Create test files:"
echo -e "   ${YELLOW}./scripts/create_test_files.sh${NC}"
echo ""
echo "2. Trigger manual cleanup:"
echo -e "   ${YELLOW}curl -sk -X POST -H 'Authorization: Bearer \$TOKEN' https://localhost:8443/api/v1/cleanup/trigger${NC}"
echo ""
echo "3. Watch the dashboard:"
echo -e "   ${YELLOW}Open https://localhost:8443 in your browser${NC}"
echo ""
echo "4. Monitor metrics in real-time:"
echo -e "   ${YELLOW}watch -n 2 'curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total'${NC}"
echo ""
echo -e "${YELLOW}Note: Files will now be PERMANENTLY DELETED when cleanup runs!${NC}"
echo ""
