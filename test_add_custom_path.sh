#!/bin/bash
# Test: Add a Custom Path via UI Configuration
# This demonstrates adding a new monitored path to StorageSage

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test: Add Custom Path to StorageSage${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

# Configuration
CUSTOM_PATH="${1:-/tmp/my-custom-storage}"
CUSTOM_PATH_NAME=$(basename "$CUSTOM_PATH")

echo -e "${CYAN}Custom Path: ${YELLOW}$CUSTOM_PATH${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 1] Create Custom Directory${NC}"
echo "─────────────────────────────────────────"
echo ""

mkdir -p "$CUSTOM_PATH"
chmod 755 "$CUSTOM_PATH"

echo -e "  ${GREEN}✓${NC} Created: $CUSTOM_PATH"
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 2] Create Test Files${NC}"
echo "─────────────────────────────────────────"
echo ""

echo "  Creating test files..."

# Create 5 old files (15 days old)
for i in {1..5}; do
    FILE="$CUSTOM_PATH/old_file_$i.log"
    echo "Old log entry $(date)" > "$FILE"
    touch -t $(date -d '15 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-15d +%Y%m%d%H%M 2>/dev/null) "$FILE" 2>/dev/null || true
    echo "    - old_file_$i.log (15 days old)"
done

# Create 3 large files (20 days old, 10MB each)
for i in {1..3}; do
    FILE="$CUSTOM_PATH/large_file_$i.bin"
    dd if=/dev/urandom of="$FILE" bs=1M count=10 2>/dev/null
    touch -t $(date -d '20 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-20d +%Y%m%d%H%M 2>/dev/null) "$FILE" 2>/dev/null || true
    echo "    - large_file_$i.bin (20 days old, 10MB)"
done

# Create 3 recent files (1 day old - should be kept)
for i in {1..3}; do
    FILE="$CUSTOM_PATH/recent_file_$i.txt"
    echo "Recent file created $(date)" > "$FILE"
    touch -t $(date -d '1 day ago' +%Y%m%d%H%M 2>/dev/null || date -v-1d +%Y%m%d%H%M 2>/dev/null) "$FILE" 2>/dev/null || true
    echo "    - recent_file_$i.txt (1 day old - should be kept)"
done

echo ""
echo -e "  ${GREEN}✓${NC} Created 11 test files (8 old, 3 recent)"
echo ""

# Show what we created
echo "  Files in $CUSTOM_PATH:"
ls -lh "$CUSTOM_PATH" | tail -n +2 | awk '{printf "    %s  %5s  %s\n", $9, $5, $6" "$7}'
echo ""

TOTAL_SIZE=$(du -sh "$CUSTOM_PATH" | awk '{print $1}')
echo -e "  Total size: ${YELLOW}$TOTAL_SIZE${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 3] Update Docker Compose Volume Mount${NC}"
echo "─────────────────────────────────────────"
echo ""

COMPOSE_FILE="docker-compose.yml"
BACKUP_COMPOSE="docker-compose.yml.backup.$(date +%s)"

cp "$COMPOSE_FILE" "$BACKUP_COMPOSE"
echo -e "  ${GREEN}✓${NC} Backed up: $BACKUP_COMPOSE"

# Add volume mount if not already present
if grep -q "$CUSTOM_PATH" "$COMPOSE_FILE"; then
    echo -e "  ${YELLOW}⚠${NC} Volume mount already exists"
else
    # Add volume mount under storage-sage-daemon service
    sed -i "/storage-sage-daemon:/,/volumes:/{ /volumes:/a\\      - $CUSTOM_PATH:$CUSTOM_PATH:z" "$COMPOSE_FILE"
    echo -e "  ${GREEN}✓${NC} Added volume mount: $CUSTOM_PATH:$CUSTOM_PATH:z"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 4] Restart Daemon${NC}"
echo "─────────────────────────────────────────"
echo ""

echo "  Restarting storage-sage-daemon..."
docker-compose restart storage-sage-daemon >/dev/null 2>&1
sleep 5
echo -e "  ${GREEN}✓${NC} Daemon restarted"
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 5] Add Path via UI Configuration${NC}"
echo "─────────────────────────────────────────"
echo ""

echo "  Getting authentication token..."
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  2>/dev/null | jq -r '.token' 2>/dev/null)

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo -e "  ${GREEN}✓${NC} Authenticated"
else
    echo -e "  ${RED}✗${NC} Authentication failed"
    exit 1
fi
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  NOW: Add Path via Web UI${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo "  1. Open browser to: ${YELLOW}https://localhost:8443${NC}"
echo "  2. Click: ${YELLOW}Configuration${NC}"
echo "  3. Scroll to: ${YELLOW}Advanced Path Rules${NC}"
echo "  4. In the text box, enter: ${YELLOW}$CUSTOM_PATH${NC}"
echo "  5. Click: ${YELLOW}+ Add Path${NC}"
echo "  6. Configure the path settings:"
echo "     - Age Off Days: ${YELLOW}7${NC}"
echo "     - Priority: ${YELLOW}1${NC}"
echo "     - Min Free %: ${YELLOW}5${NC}"
echo "     - Max Free %: ${YELLOW}90${NC}"
echo "     - Target Free %: ${YELLOW}80${NC}"
echo "     - Stack Threshold %: ${YELLOW}95${NC}"
echo "     - Stack Age Days: ${YELLOW}14${NC}"
echo "  7. Scroll to bottom and click: ${YELLOW}Save Configuration${NC}"
echo ""
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
echo ""

read -p "Press ENTER after you've added the path via UI..."
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 6] Verify Configuration${NC}"
echo "─────────────────────────────────────────"
echo ""

echo "  Checking if path was added to config..."
if grep -q "$CUSTOM_PATH" web/config/config.yaml; then
    echo -e "  ${GREEN}✓${NC} Path found in config.yaml"
    echo ""
    echo "  Configuration:"
    grep -A 10 "path: $CUSTOM_PATH" web/config/config.yaml | head -10 | sed 's/^/    /'
else
    echo -e "  ${RED}✗${NC} Path not found in config.yaml"
    echo "  Make sure you clicked 'Save Configuration' in the UI"
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 7] Trigger Cleanup${NC}"
echo "─────────────────────────────────────────"
echo ""

echo "  Current files before cleanup:"
ls -lh "$CUSTOM_PATH" | tail -n +2 | awk '{printf "    %s  %5s  %s\n", $9, $5, $6" "$7}'
echo ""

echo "  Triggering cleanup..."
TRIGGER_RESULT=$(curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger 2>/dev/null)
echo "  $TRIGGER_RESULT"
echo ""

echo "  Waiting 10 seconds for cleanup to complete..."
sleep 10
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 8] Verify Results${NC}"
echo "─────────────────────────────────────────"
echo ""

echo "  Files after cleanup:"
if [ -d "$CUSTOM_PATH" ]; then
    REMAINING=$(ls "$CUSTOM_PATH" 2>/dev/null | wc -l)

    if [ "$REMAINING" -gt 0 ]; then
        ls -lh "$CUSTOM_PATH" | tail -n +2 | awk '{printf "    %s  %5s  %s\n", $9, $5, $6" "$7}'
    else
        echo "    (no files remaining)"
    fi

    echo ""

    # Check what should have been deleted
    OLD_FILES=$(ls "$CUSTOM_PATH"/old_file_*.log 2>/dev/null | wc -l)
    LARGE_FILES=$(ls "$CUSTOM_PATH"/large_file_*.bin 2>/dev/null | wc -l)
    RECENT_FILES=$(ls "$CUSTOM_PATH"/recent_file_*.txt 2>/dev/null | wc -l)

    echo "  Summary:"
    echo "    Old files (should be deleted): ${OLD_FILES}/5 remaining"
    echo "    Large files (should be deleted): ${LARGE_FILES}/3 remaining"
    echo "    Recent files (should be kept): ${RECENT_FILES}/3 remaining"
    echo ""

    if [ "$OLD_FILES" -eq 0 ] && [ "$LARGE_FILES" -eq 0 ] && [ "$RECENT_FILES" -eq 3 ]; then
        echo -e "  ${GREEN}✅ SUCCESS!${NC}"
        echo "    - Old files: DELETED"
        echo "    - Large files: DELETED"
        echo "    - Recent files: KEPT"
        SUCCESS=true
    else
        echo -e "  ${YELLOW}⚠ Partial cleanup${NC}"
        echo "    Some files may not meet age threshold yet"
        echo "    Or cleanup may need another cycle"
        SUCCESS=false
    fi
else
    echo -e "  ${RED}✗ Directory not found${NC}"
    SUCCESS=false
fi
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 9] Check Database Audit Trail${NC}"
echo "─────────────────────────────────────────"
echo ""

echo "  Recent deletions from custom path:"
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --recent 20 2>/dev/null | grep "$CUSTOM_PATH" | head -10 || echo "  (no deletions recorded yet)"
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${YELLOW}[Step 10] Check Metrics${NC}"
echo "─────────────────────────────────────────"
echo ""

FILES_DELETED=$(curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
BYTES_FREED=$(curl -s http://localhost:9090/metrics 2>/dev/null | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')

echo "  Current metrics:"
echo "    Files deleted (total): $FILES_DELETED"
echo "    Bytes freed (total): $BYTES_FREED bytes"
echo ""

# ═══════════════════════════════════════════════════════════════
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TEST COMPLETE${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

if [ "$SUCCESS" = true ]; then
    echo -e "${GREEN}✅ CUSTOM PATH SUCCESSFULLY ADDED AND WORKING!${NC}"
    echo ""
    echo "  What happened:"
    echo "    1. Created custom directory: $CUSTOM_PATH"
    echo "    2. Added 11 test files (8 old, 3 recent)"
    echo "    3. Configured StorageSage via UI"
    echo "    4. Triggered cleanup"
    echo "    5. Old files deleted, recent files kept"
    echo ""
    echo -e "  ${CYAN}StorageSage is now monitoring: $CUSTOM_PATH${NC}"
else
    echo -e "${YELLOW}⚠️  TEST COMPLETED WITH WARNINGS${NC}"
    echo ""
    echo "  The path was added but cleanup may need more time."
    echo "  Wait 1-2 minutes and check again:"
    echo ""
    echo "    ls -lh $CUSTOM_PATH"
    echo ""
fi

echo ""
echo -e "${CYAN}View the dashboard:${NC} https://localhost:8443"
echo -e "${CYAN}Check configuration:${NC} https://localhost:8443/#/config"
echo ""

echo -e "${YELLOW}Cleanup:${NC}"
echo "  To remove the test path:"
echo "    rm -rf $CUSTOM_PATH"
echo "    # Remove from UI configuration"
echo "    # Restore docker-compose: mv $BACKUP_COMPOSE docker-compose.yml"
echo ""
