#!/bin/bash
# Test if files are ACTUALLY being deleted (not just dry-run)

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Testing: Are Files ACTUALLY Being Deleted?${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

TEST_DIR="/tmp/storage-sage-test-workspace/var/log"

# Step 1: Check daemon process for --dry-run flag
echo -e "${CYAN}[1] Checking if daemon has --dry-run flag...${NC}"
if docker exec storage-sage-daemon ps aux 2>/dev/null | grep -v grep | grep storage-sage | grep -q "\-\-dry-run"; then
    echo -e "  ${RED}✗ Daemon IS running with --dry-run flag${NC}"
    echo ""
    echo "  Process:"
    docker exec storage-sage-daemon ps aux 2>/dev/null | grep -v grep | grep storage-sage
    ACTUAL_DRY_RUN=true
else
    echo -e "  ${GREEN}✓ Daemon is NOT running with --dry-run flag${NC}"
    ACTUAL_DRY_RUN=false
fi
echo ""

# Step 2: Create a test file
echo -e "${CYAN}[2] Creating a test file...${NC}"
mkdir -p "$TEST_DIR"
TEST_FILE="$TEST_DIR/deletion_test_$(date +%s).txt"
echo "This is a test file created at $(date)" > "$TEST_FILE"

# Make it 10 days old
touch -t $(date -d '10 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-10d +%Y%m%d%H%M 2>/dev/null || echo "202411210000") "$TEST_FILE" 2>/dev/null || true

if [ -f "$TEST_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$TEST_FILE" 2>/dev/null || stat -c%s "$TEST_FILE" 2>/dev/null || echo "unknown")
    FILE_AGE=$(find "$TEST_FILE" -mtime +7 2>/dev/null && echo "Yes (>7 days)" || echo "No")
    echo -e "  ${GREEN}✓ Created: $TEST_FILE${NC}"
    echo -e "    Size: $FILE_SIZE bytes"
    echo -e "    Older than 7 days: $FILE_AGE"

    # Show file details
    ls -lh "$TEST_FILE"
else
    echo -e "  ${RED}✗ Failed to create test file${NC}"
    exit 1
fi
echo ""

# Step 3: Get current metrics
echo -e "${CYAN}[3] Current deletion metrics...${NC}"
FILES_BEFORE=$(curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
BYTES_BEFORE=$(curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')
echo -e "  Files deleted so far: ${YELLOW}${FILES_BEFORE}${NC}"
echo -e "  Bytes freed so far: ${YELLOW}${BYTES_BEFORE}${NC}"
echo ""

# Step 4: Trigger cleanup
echo -e "${CYAN}[4] Triggering manual cleanup...${NC}"
echo -n "  Authenticating... "
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  --max-time 5 2>/dev/null | jq -r '.token' 2>/dev/null)

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo -e "${GREEN}✓${NC}"

    echo -n "  Triggering cleanup... "
    TRIGGER_RESULT=$(curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
      https://localhost:8443/api/v1/cleanup/trigger --max-time 5 2>/dev/null)
    echo -e "${GREEN}✓${NC}"
    echo "  Response: $TRIGGER_RESULT"
else
    echo -e "${RED}✗ Authentication failed${NC}"
    echo "  Skipping manual trigger, will wait for automatic cleanup..."
fi
echo ""

# Step 5: Wait for cleanup
echo -e "${CYAN}[5] Waiting 10 seconds for cleanup to complete...${NC}"
for i in {10..1}; do
    echo -ne "  ${YELLOW}$i...${NC}\r"
    sleep 1
done
echo -e "  ${GREEN}Done!${NC}       "
echo ""

# Step 6: Check if file still exists
echo -e "${CYAN}[6] Checking if test file was ACTUALLY deleted...${NC}"
if [ -f "$TEST_FILE" ]; then
    echo -e "  ${RED}✗ FILE STILL EXISTS!${NC}"
    echo ""
    echo -e "  ${YELLOW}This means the daemon is in DRY-RUN mode.${NC}"
    echo -e "  ${YELLOW}Files are being identified but NOT actually deleted.${NC}"
    echo ""
    ls -lh "$TEST_FILE"
    DELETED=false
else
    echo -e "  ${GREEN}✓ FILE WAS DELETED!${NC}"
    echo ""
    echo -e "  ${GREEN}Real deletion is WORKING!${NC}"
    echo -e "  ${GREEN}The daemon is successfully deleting files.${NC}"
    DELETED=true
fi
echo ""

# Step 7: Check metrics after
echo -e "${CYAN}[7] Metrics after cleanup...${NC}"
FILES_AFTER=$(curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
BYTES_AFTER=$(curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')

echo -e "  Files deleted: ${FILES_BEFORE} → ${YELLOW}${FILES_AFTER}${NC}"
echo -e "  Bytes freed: ${BYTES_BEFORE} → ${YELLOW}${BYTES_AFTER}${NC}"

if [ "$FILES_AFTER" -gt "$FILES_BEFORE" ]; then
    echo -e "  ${GREEN}✓ Metrics increased! Files are being deleted.${NC}"
else
    echo -e "  ${YELLOW}⚠ Metrics unchanged.${NC}"
fi
echo ""

# Step 8: Check deletion log
echo -e "${CYAN}[8] Recent deletion log entries...${NC}"
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --recent 5 2>/dev/null | tail -10 || echo "  Could not query database"
echo ""

# Summary
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  TEST SUMMARY${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
echo ""

if [ "$DELETED" = true ]; then
    echo -e "${GREEN}✅ REAL DELETION IS WORKING!${NC}"
    echo ""
    echo "  The test file was ACTUALLY deleted from disk."
    echo "  The daemon is performing real file deletions."
    echo ""
    if [ "$ACTUAL_DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}Note: The process has --dry-run flag but still deleting?${NC}"
        echo -e "  ${YELLOW}This might indicate the flag is being ignored.${NC}"
    fi
    echo ""
    echo -e "  ${CYAN}The UI 'DRY-RUN MODE' badge might just be:${NC}"
    echo "    - A cached indicator"
    echo "    - Based on startup flags, not current behavior"
    echo "    - A UI bug"
    echo ""
    echo -e "  ${GREEN}Bottom line: Files ARE being deleted despite the badge!${NC}"
else
    echo -e "${RED}❌ DRY-RUN MODE IS ACTIVE${NC}"
    echo ""
    echo "  The test file was NOT deleted."
    echo "  Files are being identified but not removed."
    echo ""
    if [ "$ACTUAL_DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}Confirmed: Daemon is running with --dry-run flag${NC}"
        echo ""
        echo "  To fix:"
        echo "    1. Stop: docker-compose down"
        echo "    2. Start: docker-compose up -d"
        echo "    3. Verify: ./test_real_deletion.sh"
    fi
fi

echo ""
echo -e "${BLUE}Test complete!${NC}"
echo ""
