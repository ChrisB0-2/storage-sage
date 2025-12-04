#!/bin/bash
# Diagnose Why No Files Are Being Deleted
# This script checks common issues preventing file deletion

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  StorageSage Deletion Diagnosis${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

# Check 1: Configuration
echo -e "${CYAN}[1] Checking configuration...${NC}"
echo ""
docker exec storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null || echo "Could not read config"
echo ""

# Check 2: Scan paths configured
echo -e "${CYAN}[2] Configured scan paths:${NC}"
docker exec storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null | grep -A 10 "scan_paths:" || echo "No scan_paths found"
echo ""

# Check 3: Age threshold
echo -e "${CYAN}[3] Age threshold setting:${NC}"
AGE_THRESHOLD=$(docker exec storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null | grep "age_off_days:" | head -1 | awk '{print $2}')
echo -e "  age_off_days: ${YELLOW}$AGE_THRESHOLD${NC} days"
if [ "$AGE_THRESHOLD" = "0" ]; then
    echo -e "  ${RED}⚠️  WARNING: age_off_days is 0! No files will be deleted in AGE mode.${NC}"
    echo -e "  ${YELLOW}Suggestion: Set age_off_days to a value like 7 or 30${NC}"
fi
echo ""

# Check 4: Test directory from HOST perspective
echo -e "${CYAN}[4] Test directory on HOST:${NC}"
TEST_DIR="/tmp/storage-sage-test-workspace/var/log"
if [ -d "$TEST_DIR" ]; then
    FILE_COUNT=$(ls -1 "$TEST_DIR" 2>/dev/null | wc -l)
    echo -e "  Path: $TEST_DIR"
    echo -e "  Files: ${GREEN}$FILE_COUNT${NC}"
    if [ "$FILE_COUNT" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️  Directory is empty!${NC}"
        echo -e "  ${YELLOW}Run: ./scripts/create_test_files.sh to create test files${NC}"
    else
        echo "  Sample files:"
        ls -lh "$TEST_DIR" 2>/dev/null | head -5 | tail -4
    fi
else
    echo -e "  ${RED}✗ Directory does not exist: $TEST_DIR${NC}"
    echo -e "  Creating directory..."
    mkdir -p "$TEST_DIR"
    echo -e "  ${GREEN}✓ Created${NC}"
fi
echo ""

# Check 5: Test directory from CONTAINER perspective
echo -e "${CYAN}[5] Test directory from CONTAINER:${NC}"
echo "  Checking /test-workspace..."
docker exec storage-sage-daemon ls -la /test-workspace 2>/dev/null || echo "  /test-workspace not accessible"
echo ""
echo "  Checking /tmp/storage-sage-test-workspace..."
docker exec storage-sage-daemon ls -la /tmp/storage-sage-test-workspace 2>/dev/null || echo "  /tmp/storage-sage-test-workspace not accessible"
echo ""

# Check 6: Volume mounts
echo -e "${CYAN}[6] Docker volume mounts:${NC}"
docker inspect storage-sage-daemon --format='{{range .Mounts}}{{.Source}} → {{.Destination}} ({{.Mode}}){{println}}{{end}}' 2>/dev/null | grep -E "(test-workspace|var/log)" || echo "No test workspace mounts found"
echo ""

# Check 7: Recent daemon logs
echo -e "${CYAN}[7] Recent daemon logs (last 20 lines):${NC}"
docker logs storage-sage-daemon --tail 20 2>&1 || echo "Could not fetch logs"
echo ""

# Check 8: Metrics
echo -e "${CYAN}[8] Current metrics:${NC}"
METRICS=$(curl -s http://localhost:9090/metrics 2>/dev/null)
if [ -n "$METRICS" ]; then
    echo "  Files deleted:"
    echo "$METRICS" | grep "storagesage_files_deleted_total" | grep -v "#" || echo "    0"
    echo ""
    echo "  Bytes freed:"
    echo "$METRICS" | grep "storagesage_bytes_freed_total" | grep -v "#" || echo "    0"
    echo ""
    echo "  Last cleanup mode:"
    echo "$METRICS" | grep "storagesage_cleanup_last_mode" | grep -v "#" || echo "    Not run yet"
else
    echo -e "  ${RED}✗ Could not fetch metrics${NC}"
fi
echo ""

# Check 9: Dry-run mode
echo -e "${CYAN}[9] Checking for dry-run mode:${NC}"
docker exec storage-sage-daemon ps aux 2>/dev/null | grep storage-sage | grep -q "dry-run" && \
    echo -e "  ${RED}⚠️  DAEMON IS RUNNING IN DRY-RUN MODE!${NC}" || \
    echo -e "  ${GREEN}✓ Not in dry-run mode${NC}"
echo ""

# Summary and recommendations
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Diagnosis Summary${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo ""

# Provide actionable recommendations
echo -e "${BLUE}Common Issues and Solutions:${NC}"
echo ""

echo -e "${CYAN}Issue 1: No files in test directory${NC}"
echo "  Solution: Run ./scripts/create_test_files.sh"
echo ""

echo -e "${CYAN}Issue 2: age_off_days is 0${NC}"
echo "  Current value: $AGE_THRESHOLD"
echo "  Solution: Edit web/config/config.yaml and set age_off_days: 7"
echo "  Then restart: docker-compose restart storage-sage-daemon"
echo ""

echo -e "${CYAN}Issue 3: Files not old enough${NC}"
echo "  Check file ages: ls -lh --time-style=long-iso $TEST_DIR"
echo "  Files must be older than age_off_days threshold"
echo ""

echo -e "${CYAN}Issue 4: Wrong scan path${NC}"
echo "  Verify scan_paths in config match actual file locations"
echo "  Container must have access to the path"
echo ""

echo -e "${CYAN}Issue 5: Dry-run mode enabled${NC}"
echo "  Solution: Run ./enable_real_deletion.sh"
echo ""

echo -e "${BLUE}Quick Fix (Most Common):${NC}"
echo ""
echo "1. Create test files:"
echo -e "   ${GREEN}./scripts/create_test_files.sh${NC}"
echo ""
echo "2. Ensure age_off_days > 0 in config"
echo ""
echo "3. Trigger cleanup:"
echo -e "   ${GREEN}TOKEN=\$(curl -sk -X POST https://localhost:8443/api/v1/auth/login -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"changeme\"}' | jq -r '.token')${NC}"
echo -e "   ${GREEN}curl -sk -X POST -H \"Authorization: Bearer \$TOKEN\" https://localhost:8443/api/v1/cleanup/trigger${NC}"
echo ""
echo "4. Check results in 5 seconds:"
echo -e "   ${GREEN}curl -s http://localhost:9090/metrics | grep files_deleted_total${NC}"
echo ""
