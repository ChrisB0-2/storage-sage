#!/bin/bash

# Real-time monitoring script for StorageSage testing

DAEMON_URL="http://localhost:9090"
DB_PATH="/var/lib/storage-sage/deletions.db"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect Docker
IS_DOCKER=false
if docker compose ps 2>/dev/null | grep -q storage-sage-daemon; then
    IS_DOCKER=true
    DAEMON_CONTAINER=$(docker compose ps --format '{{.Name}}' | grep daemon | head -1)
fi

clear
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   StorageSage Real-Time Monitor${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Press Ctrl+C to exit"
echo ""

while true; do
    # Get metrics
    FILES_DELETED=$(curl -s "$DAEMON_URL/metrics" 2>/dev/null | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}' || echo "0")
    BYTES_FREED=$(curl -s "$DAEMON_URL/metrics" 2>/dev/null | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}' || echo "0")
    ERRORS=$(curl -s "$DAEMON_URL/metrics" 2>/dev/null | grep "storagesage_errors_total" | grep -v "#" | awk '{print $2}' || echo "0")
    
    BYTES_MB=$(echo "scale=2; $BYTES_FREED / 1024 / 1024" | bc 2>/dev/null || echo "0")
    
    # Get database stats
    if [ "$IS_DOCKER" = true ]; then
        DB_TOTAL=$(docker compose exec -T "$DAEMON_CONTAINER" sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions;" 2>/dev/null || echo "0")
        DB_RECENT=$(docker compose exec -T "$DAEMON_CONTAINER" sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions WHERE datetime(timestamp) > datetime('now', '-1 hour');" 2>/dev/null || echo "0")
    elif [ -f "$DB_PATH" ]; then
        DB_TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM deletions;" 2>/dev/null || echo "0")
        DB_RECENT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM deletions WHERE datetime(timestamp) > datetime('now', '-1 hour');" 2>/dev/null || echo "0")
    else
        DB_TOTAL="N/A"
        DB_RECENT="N/A"
    fi
    
    # Clear and display
    tput cup 4 0
    echo -e "${GREEN}Prometheus Metrics:${NC}"
    echo "  Files Deleted: $FILES_DELETED"
    echo "  Space Freed: ${BYTES_MB} MB"
    echo "  Errors: $ERRORS"
    echo ""
    
    echo -e "${CYAN}Database Records:${NC}"
    echo "  Total: $DB_TOTAL"
    echo "  Last hour: $DB_RECENT"
    echo ""
    
    echo -e "${YELLOW}Last Updated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
    
    # Get recent activity
    if [ "$IS_DOCKER" = true ] && [ "$DB_TOTAL" != "N/A" ] && [ "$DB_TOTAL" != "0" ]; then
        echo -e "${GREEN}Recent Activity (last 5 deletions):${NC}"
        docker compose exec -T "$DAEMON_CONTAINER" sqlite3 /var/lib/storage-sage/deletions.db \
            "SELECT datetime(timestamp, 'localtime'), action, substr(path, -30) FROM deletions ORDER BY timestamp DESC LIMIT 5;" 2>/dev/null | \
            while IFS='|' read -r ts action path; do
                if [ -n "$ts" ]; then
                    echo "  [$ts] $action ...$path"
                fi
            done
    fi
    
    sleep 2
done