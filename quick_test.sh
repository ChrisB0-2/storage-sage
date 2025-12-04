#!/bin/bash
# StorageSage Quick Test Script
# Rapid testing workflow for creating files and triggering cleanup

set -e

TEST_DIR="/tmp/storage-sage-test-workspace/var/log"
DAEMON_URL="http://localhost:9090"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== StorageSage Quick Test Script ===${NC}"
echo ""

# Ensure test directory exists
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Function to show metrics
show_metrics() {
    echo -e "${YELLOW}Current Metrics:${NC}"
    METRICS=$(curl -s "$DAEMON_URL/metrics")
    FILES_DELETED=$(echo "$METRICS" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
    BYTES_FREED=$(echo "$METRICS" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')
    ERRORS=$(echo "$METRICS" | grep "storagesage_errors_total" | grep -v "#" | awk '{print $2}')
    
    BYTES_MB=$(echo "scale=2; $BYTES_FREED / 1024 / 1024" | bc 2>/dev/null || echo "0")
    
    echo "  Files Deleted: $FILES_DELETED"
    echo "  Bytes Freed: $BYTES_MB MB"
    echo "  Errors: $ERRORS"
    echo ""
}

# Show initial state
echo -e "${GREEN}1. Initial State:${NC}"
show_metrics

# Test 1: Create old files
echo -e "${GREEN}2. Creating old files (15 days old)...${NC}"
for i in {1..3}; do
    echo "Old test file $i - $(date)" > quick_old_$i.txt
    touch -t $(date -d '15 days ago' +%Y%m%d%H%M) quick_old_$i.txt
done
echo "Created 3 old files"
echo "Files in directory: $(ls quick_old_* | wc -l)"
echo ""

# Trigger cleanup and show results
echo -e "${GREEN}3. Triggering cleanup...${NC}"
curl -s -X POST "$DAEMON_URL/trigger" > /dev/null
echo "Cleanup triggered, waiting 3 seconds..."
sleep 3

echo -e "${GREEN}4. Results after cleanup:${NC}"
show_metrics
echo "Files remaining: $(ls quick_old_* 2>/dev/null | wc -l || echo 0)"
echo ""

# Test 2: Create large files
echo -e "${GREEN}5. Creating large files (100MB each, 5 days old)...${NC}"
for i in {1..3}; do
    dd if=/dev/zero of=quick_large_$i.bin bs=1M count=100 status=none
    touch -t $(date -d '5 days ago' +%Y%m%d%H%M) quick_large_$i.bin
done
echo "Created 3 large files (300MB total)"
echo "Files in directory: $(ls quick_large_* | wc -l)"
echo "Disk usage: $(du -sh . | awk '{print $1}')"
echo ""

# Trigger cleanup and show results
echo -e "${GREEN}6. Triggering cleanup...${NC}"
curl -s -X POST "$DAEMON_URL/trigger" > /dev/null
echo "Cleanup triggered, waiting 3 seconds..."
sleep 3

echo -e "${GREEN}7. Final Results:${NC}"
show_metrics
echo "Files remaining: $(ls quick_* 2>/dev/null | wc -l || echo 0)"
echo ""

# Cleanup
echo -e "${GREEN}8. Cleaning up test files...${NC}"
rm -f quick_* 2>/dev/null || true
echo "Test directory cleaned"
echo ""

echo -e "${BLUE}=== Test Complete ===${NC}"


