#!/bin/bash
# Create Test Files for Cleanup Demonstration
#
# This script creates various test files in the monitored directory
# to demonstrate StorageSage cleanup capabilities

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TEST_DIR="/tmp/storage-sage-test-workspace/var/log"

echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Creating Test Files for StorageSage Cleanup${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
echo ""

# Ensure test directory exists
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo -e "${CYAN}Test Directory: $TEST_DIR${NC}"
echo ""

# Show current metrics
echo -e "${YELLOW}Current Metrics (Before):${NC}"
METRICS=$(curl -s http://localhost:9090/metrics 2>/dev/null)
FILES_DELETED_BEFORE=$(echo "$METRICS" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}' || echo "0")
BYTES_FREED_BEFORE=$(echo "$METRICS" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}' || echo "0")
BYTES_MB_BEFORE=$(echo "scale=2; ${BYTES_FREED_BEFORE:-0} / 1024 / 1024" | bc 2>/dev/null || echo "0")

echo -e "  Files Deleted: ${GREEN}$FILES_DELETED_BEFORE${NC}"
echo -e "  Bytes Freed: ${GREEN}$BYTES_MB_BEFORE MB${NC}"
echo ""

# Test 1: Old files (should be deleted)
echo -e "${BLUE}1. Creating OLD files (15 days old)...${NC}"
for i in {1..10}; do
    echo "Old test file $i - Created: $(date)" > "test_old_$i.log"
    # Set modification time to 15 days ago
    touch -t $(date -d '15 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-15d +%Y%m%d%H%M 2>/dev/null || echo "202411150000") "test_old_$i.log" 2>/dev/null || true
done
echo -e "${GREEN}✓ Created 10 old files (15 days old)${NC}"
ls -lh test_old_*.log | head -3
echo "  ..."
echo ""

# Test 2: Large old files (should be high priority)
echo -e "${BLUE}2. Creating LARGE old files (10MB each, 20 days old)...${NC}"
for i in {1..5}; do
    dd if=/dev/zero of="test_large_$i.bin" bs=1M count=10 status=none 2>/dev/null || head -c 10485760 /dev/zero > "test_large_$i.bin"
    touch -t $(date -d '20 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-20d +%Y%m%d%H%M 2>/dev/null || echo "202411100000") "test_large_$i.bin" 2>/dev/null || true
done
echo -e "${GREEN}✓ Created 5 large files (50MB total)${NC}"
ls -lh test_large_*.bin | head -3
echo ""

# Test 3: Recent files (should NOT be deleted)
echo -e "${BLUE}3. Creating RECENT files (1 day old - should be kept)...${NC}"
for i in {1..5}; do
    echo "Recent test file $i - Created: $(date)" > "test_recent_$i.txt"
    touch -t $(date -d '1 day ago' +%Y%m%d%H%M 2>/dev/null || date -v-1d +%Y%m%d%H%M 2>/dev/null || echo "$(date +%Y%m%d)0000") "test_recent_$i.txt" 2>/dev/null || true
done
echo -e "${GREEN}✓ Created 5 recent files (1 day old)${NC}"
echo ""

# Test 4: Mixed-age files
echo -e "${BLUE}4. Creating MIXED-AGE files for priority testing...${NC}"
for days in 8 10 12 14 16 18 20 25 30; do
    filename="test_age_${days}days.log"
    echo "File aged $days days - Created: $(date)" > "$filename"
    touch -t $(date -d "${days} days ago" +%Y%m%d%H%M 2>/dev/null || date -v-${days}d +%Y%m%d%H%M 2>/dev/null || echo "202411010000") "$filename" 2>/dev/null || true
done
echo -e "${GREEN}✓ Created 9 files with varying ages (8-30 days)${NC}"
echo ""

# Summary
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Test Files Created Summary${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo ""

TOTAL_FILES=$(ls test_* 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh . 2>/dev/null | awk '{print $1}')

echo -e "  ${CYAN}Total test files created: ${GREEN}$TOTAL_FILES${NC}"
echo -e "  ${CYAN}Total size: ${GREEN}$TOTAL_SIZE${NC}"
echo ""

echo -e "${CYAN}Breakdown:${NC}"
echo -e "  • 10 old files (15 days) - ${YELLOW}Should be DELETED${NC}"
echo -e "  • 5 large files (50MB, 20 days) - ${YELLOW}Should be DELETED (high priority)${NC}"
echo -e "  • 5 recent files (1 day) - ${GREEN}Should be KEPT${NC}"
echo -e "  • 9 mixed-age files (8-30 days) - ${YELLOW}Some DELETED based on age threshold${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

echo "1. Wait for automatic cleanup (interval: 1 minute)"
echo "   OR trigger manual cleanup:"
echo ""
echo -e "   ${YELLOW}# Get auth token${NC}"
echo -e "   ${GREEN}TOKEN=\$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \\${NC}"
echo -e "   ${GREEN}     -H 'Content-Type: application/json' \\${NC}"
echo -e "   ${GREEN}     -d '{\"username\":\"admin\",\"password\":\"changeme\"}' \\${NC}"
echo -e "   ${GREEN}     | jq -r '.token')${NC}"
echo ""
echo -e "   ${YELLOW}# Trigger cleanup${NC}"
echo -e "   ${GREEN}curl -sk -X POST -H \"Authorization: Bearer \$TOKEN\" \\${NC}"
echo -e "   ${GREEN}     https://localhost:8443/api/v1/cleanup/trigger${NC}"
echo ""

echo "2. Monitor the cleanup:"
echo -e "   ${YELLOW}watch -n 2 'curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total'${NC}"
echo ""

echo "3. Check which files were deleted:"
echo -e "   ${YELLOW}ls -lh $TEST_DIR/test_*${NC}"
echo ""

echo "4. View deletion log in database:"
echo -e "   ${YELLOW}docker exec storage-sage-daemon storage-sage-query \\${NC}"
echo -e "   ${YELLOW}     --db /var/lib/storage-sage/deletions.db --recent 20${NC}"
echo ""

echo "5. Watch the Web UI in real-time:"
echo -e "   ${YELLOW}Open https://localhost:8443 in your browser${NC}"
echo ""

echo -e "${GREEN}✅ Test files ready for cleanup demonstration!${NC}"
echo ""
