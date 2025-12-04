#!/bin/bash
# Disable Dry-Run Mode - Enable Real Deletions
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Disabling DRY-RUN Mode${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}⚠️  WARNING: This will enable REAL file deletion!${NC}"
echo ""
echo "After this, files will be PERMANENTLY DELETED from disk."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 1: Checking current Dockerfile...${NC}"
CURRENT_CMD=$(grep "^CMD" cmd/storage-sage/Dockerfile | grep -o "dry-run" || echo "")
if [ -n "$CURRENT_CMD" ]; then
    echo -e "${RED}✗ Dockerfile has --dry-run flag!${NC}"
    echo "  Removing --dry-run from CMD..."
    sed -i 's/--dry-run//g' cmd/storage-sage/Dockerfile
    echo -e "${GREEN}✓ Removed --dry-run from Dockerfile${NC}"
else
    echo -e "${GREEN}✓ No --dry-run in Dockerfile${NC}"
fi
echo ""

echo -e "${BLUE}Step 2: Checking for environment variable...${NC}"
# Check docker-compose.yml for DRY_RUN env var
if grep -q "DRY_RUN" docker-compose.yml 2>/dev/null; then
    echo -e "${YELLOW}Found DRY_RUN in docker-compose.yml${NC}"
    echo "  Removing..."
    sed -i '/DRY_RUN/d' docker-compose.yml
    echo -e "${GREEN}✓ Removed${NC}"
else
    echo -e "${GREEN}✓ No DRY_RUN env var${NC}"
fi
echo ""

echo -e "${BLUE}Step 3: Checking docker-compose override...${NC}"
if [ -f "docker-compose.override.yml" ]; then
    if grep -q "dry-run" docker-compose.override.yml 2>/dev/null; then
        echo -e "${YELLOW}Found --dry-run in docker-compose.override.yml${NC}"
        echo "  Contents:"
        cat docker-compose.override.yml
        echo ""
        read -p "Remove docker-compose.override.yml? (yes/no): " remove_override
        if [ "$remove_override" = "yes" ]; then
            mv docker-compose.override.yml docker-compose.override.yml.backup
            echo -e "${GREEN}✓ Moved to .backup${NC}"
        fi
    fi
else
    echo -e "${GREEN}✓ No override file${NC}"
fi
echo ""

echo -e "${BLUE}Step 4: Stopping daemon...${NC}"
docker-compose stop storage-sage-daemon 2>/dev/null || docker compose stop storage-sage-daemon
echo -e "${GREEN}✓ Stopped${NC}"
echo ""

echo -e "${BLUE}Step 5: Rebuilding daemon image...${NC}"
docker-compose build --no-cache storage-sage-daemon 2>/dev/null || docker compose build --no-cache storage-sage-daemon
echo -e "${GREEN}✓ Rebuilt${NC}"
echo ""

echo -e "${BLUE}Step 6: Starting daemon...${NC}"
docker-compose up -d storage-sage-daemon 2>/dev/null || docker compose up -d storage-sage-daemon
echo -e "${GREEN}✓ Started${NC}"
echo ""

echo -e "${BLUE}Step 7: Waiting for daemon to be ready...${NC}"
sleep 5
echo -e "${GREEN}✓ Ready${NC}"
echo ""

echo -e "${BLUE}Step 8: Verifying daemon is running...${NC}"
if docker ps 2>/dev/null | grep -q storage-sage-daemon; then
    echo -e "${GREEN}✓ Daemon is running${NC}"

    # Check process args
    echo ""
    echo "Process command:"
    docker exec storage-sage-daemon ps aux 2>/dev/null | grep storage-sage | grep -v grep || echo "  Could not check process"

    # Check for dry-run flag
    if docker exec storage-sage-daemon ps aux 2>/dev/null | grep storage-sage | grep -q "dry-run"; then
        echo -e "${RED}✗ Still running with --dry-run!${NC}"
        echo ""
        echo "Manual fix required:"
        echo "1. Check: docker inspect storage-sage-daemon --format='{{.Args}}'"
        echo "2. Check: docker-compose config | grep -A 20 storage-sage-daemon"
    else
        echo -e "${GREEN}✓ No --dry-run flag detected!${NC}"
    fi
else
    echo -e "${RED}✗ Daemon not running!${NC}"
    echo "Check logs: docker logs storage-sage-daemon"
    exit 1
fi
echo ""

echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Dry-Run Mode Disabled!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Refresh the Web UI:"
echo -e "   ${YELLOW}https://localhost:8443${NC}"
echo "   The 'DRY-RUN MODE' badge should disappear"
echo ""
echo "2. Create test files:"
echo -e "   ${YELLOW}./scripts/create_test_files.sh${NC}"
echo ""
echo "3. Trigger cleanup:"
echo -e "   ${YELLOW}# Use the 'Manual Cleanup' button in the UI${NC}"
echo "   # OR via API:"
echo ""
echo -e '   TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \\'
echo -e '     -H "Content-Type: application/json" \\'
echo -e '     -d '"'"'{"username":"admin","password":"changeme"}'"'"' \\'
echo -e '     | jq -r '"'"'.token'"'"')'
echo ""
echo -e '   curl -sk -X POST -H "Authorization: Bearer $TOKEN" \\'
echo -e '     https://localhost:8443/api/v1/cleanup/trigger'
echo ""
echo "4. Watch files get ACTUALLY deleted:"
echo -e "   ${YELLOW}ls -lh /tmp/storage-sage-test-workspace/var/log/test_*${NC}"
echo ""
echo -e "${RED}⚠️  Files will now be PERMANENTLY DELETED when cleanup runs!${NC}"
echo ""
