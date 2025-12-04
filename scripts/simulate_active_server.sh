#!/bin/bash
# StorageSage Active Server Simulation
# Creates realistic server-like file patterns and tests cleanup
#
# NOTE: If daemon cleanup interval is very short (e.g., 1 minute), files may
# be deleted during creation. For better simulation results, consider
# temporarily increasing interval_minutes in web/config/config.yaml

set -e

TEST_DIR="/tmp/storage-sage-test-workspace/var/log"
DAEMON_URL="http://localhost:9090"
BACKEND_URL="https://localhost:8443"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   StorageSage Active Server Simulation               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ensure test directory exists
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Function to show metrics
show_metrics() {
    METRICS=$(curl -s "$DAEMON_URL/metrics" 2>/dev/null || echo "")
    if [ -z "$METRICS" ]; then
        echo -e "${RED}⚠️  Cannot connect to daemon metrics${NC}"
        return
    fi
    
    FILES_DELETED=$(echo "$METRICS" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}' || echo "0")
    BYTES_FREED=$(echo "$METRICS" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}' || echo "0")
    ERRORS=$(echo "$METRICS" | grep "storagesage_errors_total" | grep -v "#" | awk '{print $2}' || echo "0")
    
    # Fix: Handle empty values
    if [ -z "$BYTES_FREED" ] || [ "$BYTES_FREED" = "" ]; then
        BYTES_FREED="0"
    fi
    
    # Fix: Better parsing
    if command -v bc &> /dev/null && [ -n "$BYTES_FREED" ] && [ "$BYTES_FREED" != "0" ]; then
        BYTES_MB=$(echo "scale=2; $BYTES_FREED / 1024 / 1024" | bc 2>/dev/null || echo "0")
    else
        BYTES_MB="0"
    fi
    
    echo -e "${YELLOW}📊 Current Metrics:${NC}"
    echo "  Files Deleted: $FILES_DELETED"
    echo "  Bytes Freed: $BYTES_MB MB"
    echo "  Errors: $ERRORS"
}

# Function to get file count
get_file_count() {
    find "$TEST_DIR" -type f 2>/dev/null | wc -l
}

# Function to get file count with breakdown
get_file_count_verbose() {
    local total=$(find "$TEST_DIR" -type f 2>/dev/null | wc -l)
    local app_count=$(find "$TEST_DIR/app" -type f 2>/dev/null | wc -l)
    local temp_count=$(find "$TEST_DIR/temp" -type f 2>/dev/null | wc -l)
    local backups_count=$(find "$TEST_DIR/backups" -type f 2>/dev/null | wc -l)
    echo "Total: $total (app: $app_count, temp: $temp_count, backups: $backups_count)"
}

# Function to get disk usage
get_disk_usage() {
    du -sh "$TEST_DIR" 2>/dev/null | awk '{print $1}'
}

# Function to trigger cleanup
trigger_cleanup() {
    echo -e "${BLUE}🔄 Triggering cleanup...${NC}"
    RESPONSE=$(curl -s -X POST "$DAEMON_URL/trigger" 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}  Warning: Trigger endpoint may not be available${NC}"
        echo "  Response: $RESPONSE"
    fi
    # Increase wait time for cleanup to complete
    sleep 5
}

# Function to create files with specific age
create_aged_file() {
    local filename=$1
    local age_days=$2
    local size_mb=${3:-1}
    
    # Ensure we're in the right directory
    cd "$TEST_DIR" 2>/dev/null || return 1
    
    # Create file with full path
    local full_path="$TEST_DIR/$filename"
    mkdir -p "$(dirname "$full_path")"
    
    # Create file
    if ! dd if=/dev/zero of="$full_path" bs=1M count=$size_mb status=none 2>/dev/null; then
        echo "Error: Failed to create $full_path" >&2
        return 1
    fi
    
    # Set modification time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        touch -t $(date -v-${age_days}d +%Y%m%d%H%M) "$full_path"
    else
        # Linux
        touch -t $(date -d "${age_days} days ago" +%Y%m%d%H%M) "$full_path"
    fi
    
    # Verify file was created
    if [ ! -f "$full_path" ]; then
        echo "Warning: File creation may have failed: $full_path" >&2
        return 1
    fi
}

# Function to pause daemon cleanup (if possible)
pause_daemon() {
    echo -e "${YELLOW}Pausing daemon cleanup cycles...${NC}"
    # Try to send a signal to pause (if daemon supports it)
    # Or we can check the interval and warn
    INTERVAL=$(docker compose exec -T storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null | grep "interval_minutes" | awk '{print $2}' || echo "unknown")
    echo "  Current cleanup interval: $INTERVAL minutes"
    if [ "$INTERVAL" = "1" ]; then
        echo -e "  ${YELLOW}⚠ Warning: Daemon runs cleanup every 1 minute - files may be deleted quickly${NC}"
        echo "  Consider increasing interval_minutes in config.yaml for testing"
    fi
}

# Function to resume daemon cleanup
resume_daemon() {
    echo -e "${GREEN}Resuming daemon cleanup cycles...${NC}"
    # Trigger a cleanup to resume normal operation
    trigger_cleanup
}

echo -e "${GREEN}Phase 1: Creating Initial Server State${NC}"
echo "─────────────────────────────────────────"

# Create directory structure like a real server
mkdir -p "$TEST_DIR"/{app,nginx,apache,system,backups,temp}

# Create old log files (15+ days - should be deleted)
echo -e "${YELLOW}Creating old log files (15-20 days old)...${NC}"
for i in {1..50}; do
    create_aged_file "app/app_old_$i.log" $((15 + i % 5)) 1
done
for i in {1..30}; do
    create_aged_file "nginx/access_old_$i.log" $((16 + i % 4)) 2
done
for i in {1..20}; do
    create_aged_file "apache/error_old_$i.log" $((17 + i % 3)) 1
done

# Create medium-age files (8-12 days - borderline)
echo -e "${YELLOW}Creating medium-age files (8-12 days old)...${NC}"
for i in {1..30}; do
    create_aged_file "app/app_medium_$i.log" $((8 + i % 4)) 1
done

# Create recent files (0-5 days - should NOT be deleted)
echo -e "${YELLOW}Creating recent files (0-5 days old)...${NC}"
for i in {1..20}; do
    create_aged_file "app/app_recent_$i.log" $((i % 5)) 1
done

# Create large old backup files (should be deleted)
echo -e "${YELLOW}Creating large old backup files (20 days old, 10MB each)...${NC}"
for i in {1..10}; do
    create_aged_file "backups/backup_old_$i.tar.gz" 20 10
done

INITIAL_COUNT=$(get_file_count)
INITIAL_SIZE=$(get_disk_usage)

echo ""
echo -e "${GREEN}Initial State:${NC}"
echo "  Files created: $INITIAL_COUNT"
echo "  Disk usage: $INITIAL_SIZE"
show_metrics
echo ""

# Trigger first cleanup
echo -e "${GREEN}Phase 2: First Cleanup Cycle${NC}"
echo "─────────────────────────────────────────"
trigger_cleanup

AFTER_CLEANUP_COUNT=$(get_file_count)
AFTER_CLEANUP_SIZE=$(get_disk_usage)

echo -e "${GREEN}After Cleanup:${NC}"
echo "  Files remaining: $AFTER_CLEANUP_COUNT"
echo "  Disk usage: $AFTER_CLEANUP_SIZE"
echo "  Files deleted: $((INITIAL_COUNT - AFTER_CLEANUP_COUNT))"
show_metrics
echo ""

# Simulate ongoing server activity
echo -e "${GREEN}Phase 3: Simulating Ongoing Server Activity${NC}"
echo "─────────────────────────────────────────"

# Check daemon interval before starting
pause_daemon
echo ""

# Verify daemon scan path
echo "Checking daemon configuration..."
DAEMON_SCAN_PATHS=$(docker compose exec -T storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null | grep -E "^\s*-\s*/" || echo "")
echo "  Daemon scan paths:"
echo "$DAEMON_SCAN_PATHS" | sed 's/^/    /' || echo "    (none found)"
echo "  Test directory: $TEST_DIR"
echo "  Container path: /test-workspace/var/log"
echo ""

# Create new files continuously (simulating active server)
echo -e "${YELLOW}Creating new files every 5 seconds (simulating active server)...${NC}"
echo "Press Ctrl+C to stop file creation"

# Get baseline count with breakdown
BASELINE_COUNT=$(get_file_count)
echo "  Baseline file count: $BASELINE_COUNT"
get_file_count_verbose
echo -e "  ${YELLOW}Note: Daemon may delete files during creation if cleanup cycle runs${NC}"
echo ""

# Track which files exist before each round
BEFORE_ROUND_FILES=$(find "$TEST_DIR" -type f -name "*.log" -o -name "*.tmp" 2>/dev/null | wc -l)

for round in {1..10}; do
    CREATED_THIS_ROUND=0
    FAILED_THIS_ROUND=0
    
    # Get file list before creation
    FILES_BEFORE=$(find "$TEST_DIR" -type f 2>/dev/null | sort)
    COUNT_BEFORE=$(echo "$FILES_BEFORE" | wc -l)
    
    # Create all files quickly in one batch
    for i in {1..5}; do
        if create_aged_file "app/app_live_${round}_$i.log" 0 1; then
            CREATED_THIS_ROUND=$((CREATED_THIS_ROUND + 1))
        else
            FAILED_THIS_ROUND=$((FAILED_THIS_ROUND + 1))
        fi
    done
    
    for i in {1..3}; do
        if create_aged_file "temp/temp_${round}_$i.tmp" 0 1; then
            CREATED_THIS_ROUND=$((CREATED_THIS_ROUND + 1))
        else
            FAILED_THIS_ROUND=$((FAILED_THIS_ROUND + 1))
        fi
    done
    
    # Get file list immediately after creation
    FILES_AFTER=$(find "$TEST_DIR" -type f 2>/dev/null | sort)
    COUNT_AFTER=$(echo "$FILES_AFTER" | wc -l)
    
    # Find files that were added
    NEW_FILES=$(comm -13 <(echo "$FILES_BEFORE") <(echo "$FILES_AFTER"))
    NEW_COUNT=$(echo "$NEW_FILES" | grep -v '^$' | wc -l)
    
    # Find files that were deleted
    DELETED_FILES=$(comm -23 <(echo "$FILES_BEFORE") <(echo "$FILES_AFTER"))
    DELETED_COUNT=$(echo "$DELETED_FILES" | grep -v '^$' | wc -l)
    
    # Check immediately after creation
    IMMEDIATE_COUNT=$(get_file_count)
    IMMEDIATE_INCREASE=$((IMMEDIATE_COUNT - BASELINE_COUNT))
    
    # Wait a moment, then check again (daemon might delete some)
    sleep 2
    CURRENT_COUNT=$(get_file_count)
    ACTUAL_INCREASE=$((CURRENT_COUNT - BASELINE_COUNT))
    
    echo "  Round $round: Created $CREATED_THIS_ROUND files (failed: $FAILED_THIS_ROUND)"
    echo "    Count before: $COUNT_BEFORE, after creation: $COUNT_AFTER"
    echo "    New files added: $NEW_COUNT, files deleted: $DELETED_COUNT"
    echo "    Net change: +$((COUNT_AFTER - COUNT_BEFORE))"
    echo "    Immediately after: $IMMEDIATE_COUNT files (+$IMMEDIATE_INCREASE)"
    echo "    After 2s wait: $CURRENT_COUNT files (+$ACTUAL_INCREASE)"
    
    # Show sample of deleted files if any
    if [ "$DELETED_COUNT" -gt 0 ]; then
        echo -e "    ${YELLOW}⚠ $DELETED_COUNT files were deleted during creation:${NC}"
        echo "$DELETED_FILES" | head -3 | sed 's/^/      /'
        if [ "$DELETED_COUNT" -gt 3 ]; then
            echo "      ... and $((DELETED_COUNT - 3)) more"
        fi
    fi
    
    # Check if files are being deleted
    if [ "$ACTUAL_INCREASE" -lt "$IMMEDIATE_INCREASE" ]; then
        DELETED=$((IMMEDIATE_INCREASE - ACTUAL_INCREASE))
        echo -e "    ${YELLOW}⚠ $DELETED more files deleted by daemon in 2 seconds${NC}"
    fi
    
    # Check if any of the files we just created still exist
    EXISTING=$(find "$TEST_DIR/app" -name "app_live_${round}_*.log" 2>/dev/null | wc -l)
    echo "    Files from round $round still exist: $EXISTING/5"
    
    BASELINE_COUNT=$CURRENT_COUNT
    sleep 3  # Reduced from 5 to 3 since we already waited 2 seconds
done

echo ""
CURRENT_COUNT=$(get_file_count)
CURRENT_SIZE=$(get_disk_usage)

echo -e "${GREEN}After Activity Simulation:${NC}"
echo "  Total files: $CURRENT_COUNT"
get_file_count_verbose
echo "  Disk usage: $CURRENT_SIZE"
echo ""

# Phase 4: Simulating Disk Pressure
echo -e "${GREEN}Phase 4: Simulating Disk Pressure${NC}"
echo "─────────────────────────────────────────"

echo -e "${YELLOW}Creating many large files to trigger disk threshold cleanup...${NC}"
cd "$TEST_DIR"  # Ensure we're in the right directory

BEFORE_CREATE_COUNT=$(get_file_count)
CREATED_FILES=0
FAILED_FILES=0

echo "  Creating 50 files (5MB each) as quickly as possible..."
# Create all files in rapid succession to minimize deletion window
for i in {1..50}; do
    if create_aged_file "backups/disk_pressure_$i.bin" 5 5; then
        CREATED_FILES=$((CREATED_FILES + 1))
    else
        FAILED_FILES=$((FAILED_FILES + 1))
    fi
done

# Check immediately
IMMEDIATE_COUNT=$(get_file_count)
IMMEDIATE_INCREASE=$((IMMEDIATE_COUNT - BEFORE_CREATE_COUNT))

# Wait a moment for daemon to potentially delete
sleep 3
AFTER_CREATE_COUNT=$(get_file_count)
ACTUAL_CREATED=$((AFTER_CREATE_COUNT - BEFORE_CREATE_COUNT))

DISK_PRESSURE_COUNT=$(get_file_count)
DISK_PRESSURE_SIZE=$(get_disk_usage)

echo "  Files before creation: $BEFORE_CREATE_COUNT"
echo "  Attempted to create: 50 files"
echo "  Successfully created: $CREATED_FILES files"
echo "  Failed to create: $FAILED_FILES files"
echo "  Files immediately after creation: $IMMEDIATE_COUNT (+$IMMEDIATE_INCREASE)"
echo "  Files after 3s wait: $DISK_PRESSURE_COUNT (+$ACTUAL_CREATED)"
echo "  Disk usage: $DISK_PRESSURE_SIZE"

if [ "$ACTUAL_CREATED" -lt "$IMMEDIATE_INCREASE" ]; then
    DELETED=$((IMMEDIATE_INCREASE - ACTUAL_CREATED))
    echo -e "  ${YELLOW}⚠ $DELETED files deleted by daemon in 3 seconds${NC}"
    echo "  This is expected if daemon cleanup cycle runs during file creation"
fi

if [ "$ACTUAL_CREATED" -lt "$CREATED_FILES" ]; then
    echo -e "  ${YELLOW}⚠ Warning: Files may be getting deleted as they're created${NC}"
    echo "  Checking if daemon is running cleanup cycles..."
    # Check daemon logs for recent cleanup activity
    echo "  Recent daemon activity:"
    docker compose logs --tail=10 storage-sage-daemon 2>/dev/null | grep -i "cleanup\|delete\|scan" | tail -5 || echo "    (Cannot check daemon logs)"
fi

echo ""

# After Phase 4 file creation, before cleanup
echo "Checking disk usage..."
df -h /tmp/storage-sage-test-workspace 2>/dev/null || df -h /tmp

echo "Checking config thresholds..."
# Fix: Use proper path and command
CONFIG_OUTPUT=$(docker compose exec -T storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null)
if [ -n "$CONFIG_OUTPUT" ]; then
    echo "$CONFIG_OUTPUT" | grep -E "(max_free_percent|stack_threshold|min_free_percent)" || echo "  No threshold settings found in config"
else
    echo "  Config file not accessible in container"
    echo "  Trying alternative path..."
    docker compose exec -T storage-sage-daemon ls -la /etc/storage-sage/ 2>/dev/null || echo "  Cannot list config directory"
fi
echo ""

# Check if test workspace is being scanned
echo "Checking if test workspace is in scan paths..."
SCAN_PATHS=$(docker compose exec -T storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null | grep -E "^\s*-\s*/" || echo "")
if echo "$SCAN_PATHS" | grep -q "test-workspace"; then
    echo "  ✓ Test workspace is in scan paths"
else
    echo "  ⚠ Test workspace may not be in scan paths"
    echo "  Scan paths found:"
    echo "$SCAN_PATHS" | sed 's/^/    /'
fi
echo ""

trigger_cleanup

AFTER_DISK_CLEANUP_COUNT=$(get_file_count)
AFTER_DISK_CLEANUP_SIZE=$(get_disk_usage)

echo -e "${GREEN}After Disk Pressure Cleanup:${NC}"
echo "  Files remaining: $AFTER_DISK_CLEANUP_COUNT"
echo "  Disk usage: $AFTER_DISK_CLEANUP_SIZE"
echo "  Files deleted: $((DISK_PRESSURE_COUNT - AFTER_DISK_CLEANUP_COUNT))"
show_metrics
echo ""

# Check database records
echo -e "${GREEN}Phase 5: Checking Database Records${NC}"
echo "─────────────────────────────────────────"

# Check if database is enabled in config
DB_ENABLED=$(docker compose exec -T storage-sage-daemon cat /etc/storage-sage/config.yaml 2>/dev/null | grep -E "database_path" || echo "")
if [ -z "$DB_ENABLED" ]; then
    echo -e "${YELLOW}⚠ Database may not be enabled in config${NC}"
    echo "  Add 'database_path: /var/lib/storage-sage/deletions.db' to config.yaml"
fi

# Query database in container
if docker ps --format '{{.Names}}' | grep -q storage-sage-daemon; then
    echo "Querying database in container..."
    TOTAL_RECORDS=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions;" 2>/dev/null || echo "0")
    DELETE_RECORDS=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions WHERE action='DELETE';" 2>/dev/null || echo "0")
    SKIP_RECORDS=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions WHERE action='SKIP';" 2>/dev/null || echo "0")
    
    echo -e "${YELLOW}Database Statistics:${NC}"
    echo "  Total records: $TOTAL_RECORDS"
    echo "  DELETE records: $DELETE_RECORDS"
    echo "  SKIP records: $SKIP_RECORDS"
    echo ""
    
    if [ "$TOTAL_RECORDS" != "0" ]; then
        echo -e "${YELLOW}Recent deletions (last 5):${NC}"
        docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT datetime(timestamp, 'localtime'), action, substr(path, -40), size/1024/1024 FROM deletions ORDER BY timestamp DESC LIMIT 5;" 2>/dev/null | while IFS='|' read -r ts action path size; do
            if [ -n "$ts" ]; then
                echo "  [$ts] $action: ...$path (${size}MB)"
            fi
        done
    else
        echo -e "${YELLOW}No database records found${NC}"
        echo "  This could mean:"
        echo "    1. Database is not enabled in config"
        echo "    2. Database path is incorrect"
        echo "    3. Deletions are not being logged"
    fi
else
    echo -e "${YELLOW}Daemon container not running${NC}"
fi

echo ""

# Final summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Simulation Complete                                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Final State:${NC}"
echo "  Files remaining: $(get_file_count)"
echo "  Disk usage: $(get_disk_usage)"
show_metrics
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. View deletion log in UI: https://localhost:8443/deletions"
echo "  2. Check metrics: curl $DAEMON_URL/metrics"
echo "  3. Monitor in real-time: ./monitor_cleanup.sh"
echo "  4. View database: docker compose exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db 'SELECT COUNT(*) FROM deletions;'"
echo ""


