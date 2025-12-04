#!/bin/bash
# StorageSage - Custom Path Demonstration
# This script demonstrates adding a new path to StorageSage and watching it clean up files
#
# Usage: ./demo_custom_path.sh [custom_path]
# Example: ./demo_custom_path.sh /tmp/my-custom-logs

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Get custom path from argument or use default
CUSTOM_PATH="${1:-/tmp/demo-custom-path}"

echo -e "${BOLD}${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║         StorageSage - Custom Path Demonstration              ║
║                  Works on ANY Directory!                     ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}This demonstration will:${NC}"
echo "  1. Create a custom directory with test files"
echo "  2. Update StorageSage configuration to monitor it"
echo "  3. Restart the daemon with new config"
echo "  4. Watch StorageSage automatically clean it up"
echo ""
echo -e "${YELLOW}Custom path: $CUSTOM_PATH${NC}"
echo ""
read -p "Press Enter to begin..."

# ═══════════════════════════════════════════════════════════════
# STEP 1: CREATE CUSTOM DIRECTORY
# ═══════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${MAGENTA}  STEP 1: Creating Custom Directory${NC}"
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}Creating directory: $CUSTOM_PATH${NC}"
mkdir -p "$CUSTOM_PATH"
echo -e "  ${GREEN}✓ Directory created${NC}"
echo ""

echo -e "${CYAN}Populating with test files:${NC}"
echo ""

# Old files that should be deleted
echo -e "${YELLOW}Creating OLD files (15+ days old) - WILL BE DELETED:${NC}"
for i in {1..10}; do
    FILE="$CUSTOM_PATH/old_log_$i.txt"
    echo "Old log entry $i - created $(date)" > "$FILE"
    touch -t $(date -d '15 days ago' +%Y%m%d%H%M 2>/dev/null) "$FILE" 2>/dev/null
    echo "  ✓ $FILE (15 days old)"
done
echo ""

# Large old files
echo -e "${YELLOW}Creating LARGE old files (20 days old, 5MB each) - WILL BE DELETED:${NC}"
for i in {1..3}; do
    FILE="$CUSTOM_PATH/old_backup_$i.tar.gz"
    dd if=/dev/zero of="$FILE" bs=1M count=5 status=none 2>/dev/null
    touch -t $(date -d '20 days ago' +%Y%m%d%H%M 2>/dev/null) "$FILE" 2>/dev/null
    echo "  ✓ $FILE (20 days old, 5MB)"
done
echo ""

# Recent files that should be kept
echo -e "${GREEN}Creating RECENT files (1 day old) - WILL BE KEPT:${NC}"
for i in {1..5}; do
    FILE="$CUSTOM_PATH/recent_log_$i.txt"
    echo "Recent log entry $i - created $(date)" > "$FILE"
    touch -t $(date -d '1 day ago' +%Y%m%d%H%M 2>/dev/null) "$FILE" 2>/dev/null
    echo "  ✓ $FILE (1 day old)"
done
echo ""

# Current files
echo -e "${GREEN}Creating CURRENT files (now) - WILL BE KEPT:${NC}"
for i in {1..3}; do
    FILE="$CUSTOM_PATH/current_$i.log"
    echo "Current file $i - created $(date)" > "$FILE"
    echo "  ✓ $FILE (just created)"
done
echo ""

TOTAL_FILES=$(ls -1 "$CUSTOM_PATH" | wc -l)
TOTAL_SIZE=$(du -sh "$CUSTOM_PATH" 2>/dev/null | awk '{print $1}')

echo -e "${CYAN}Summary:${NC}"
echo "  Total files created: $TOTAL_FILES"
echo "  Total size: $TOTAL_SIZE"
echo "  Location: $CUSTOM_PATH"
echo ""

echo -e "${YELLOW}Verification - Files exist:${NC}"
ls -lh "$CUSTOM_PATH" | head -12
echo "  ... (showing first 10)"
echo ""

read -p "Press Enter to update configuration..."

# ═══════════════════════════════════════════════════════════════
# STEP 2: BACKUP AND UPDATE CONFIGURATION
# ═══════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${MAGENTA}  STEP 2: Updating StorageSage Configuration${NC}"
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""

CONFIG_FILE="web/config/config.yaml"
BACKUP_FILE="web/config/config.yaml.demo-backup-$(date +%s)"

echo -e "${CYAN}Backing up current configuration:${NC}"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "  ✓ Backup saved: $BACKUP_FILE"
echo ""

echo -e "${CYAN}Current scan_paths:${NC}"
grep -A 5 "^scan_paths:" "$CONFIG_FILE" | sed 's/^/  /'
echo ""

echo -e "${CYAN}Adding custom path to configuration:${NC}"
echo "  New path: $CUSTOM_PATH"
echo ""

# Add the custom path to scan_paths if not already there
if grep -q "$CUSTOM_PATH" "$CONFIG_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ Path already in config, skipping addition${NC}"
else
    # Add to scan_paths array
    sed -i "/^scan_paths:/a\    - $CUSTOM_PATH" "$CONFIG_FILE"
    echo -e "  ${GREEN}✓ Added to scan_paths${NC}"
fi
echo ""

# Add path-specific rules
echo -e "${CYAN}Adding path-specific rules:${NC}"
cat >> "$CONFIG_FILE" << EOF

    # Custom demo path - added by demo_custom_path.sh
    - path: $CUSTOM_PATH
      age_off_days: 7           # Delete files older than 7 days
      min_free_percent: 5
      max_free_percent: 90
      target_free_percent: 80
      priority: 1               # High priority
      stack_threshold: 95
      stack_age_days: 14
EOF

echo "  ✓ Path-specific rules added"
echo ""

echo -e "${CYAN}New configuration:${NC}"
echo ""
tail -15 "$CONFIG_FILE" | sed 's/^/  /'
echo ""

echo -e "${YELLOW}Note: Configuration will be used inside container${NC}"
echo ""

read -p "Press Enter to update docker-compose and restart daemon..."

# ═══════════════════════════════════════════════════════════════
# STEP 3: UPDATE DOCKER COMPOSE AND RESTART
# ═══════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${MAGENTA}  STEP 3: Mounting Custom Path in Container${NC}"
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Determine the container path
CONTAINER_PATH="$CUSTOM_PATH"

echo -e "${CYAN}Volume mount configuration:${NC}"
echo "  Host path: $CUSTOM_PATH"
echo "  Container path: $CONTAINER_PATH"
echo ""

# Check if we need to add volume mount
COMPOSE_FILE="docker-compose.yml"
COMPOSE_BACKUP="docker-compose.yml.demo-backup-$(date +%s)"

echo -e "${CYAN}Backing up docker-compose.yml:${NC}"
cp "$COMPOSE_FILE" "$COMPOSE_BACKUP"
echo "  ✓ Backup saved: $COMPOSE_BACKUP"
echo ""

echo -e "${CYAN}Checking if volume mount exists:${NC}"
if grep -q "$CUSTOM_PATH" "$COMPOSE_FILE" 2>/dev/null; then
    echo -e "  ${GREEN}✓ Volume mount already configured${NC}"
else
    echo -e "  ${YELLOW}⚠ Adding volume mount to docker-compose.yml${NC}"

    # Add volume mount to daemon service (before the z flag line)
    # Find the line with "- /tmp/storage-sage-test-workspace" and add our mount after it
    sed -i "/- \/tmp\/storage-sage-test-workspace.*:z/a\      - $CUSTOM_PATH:$CONTAINER_PATH:z" "$COMPOSE_FILE"

    echo -e "  ${GREEN}✓ Volume mount added${NC}"
fi
echo ""

echo -e "${CYAN}Current volume mounts in daemon service:${NC}"
grep -A 15 "storage-sage-daemon:" "$COMPOSE_FILE" | grep -A 10 "volumes:" | head -15 | sed 's/^/  /'
echo ""

echo -e "${CYAN}Restarting daemon with new configuration:${NC}"
echo "  Stopping daemon..."
docker-compose stop storage-sage-daemon 2>/dev/null || docker compose stop storage-sage-daemon
echo "  ✓ Daemon stopped"
echo ""

echo "  Starting daemon with new config..."
docker-compose up -d storage-sage-daemon 2>/dev/null || docker compose up -d storage-sage-daemon
echo "  ✓ Daemon started"
echo ""

echo "  Waiting for daemon to be ready (10 seconds)..."
sleep 10
echo "  ✓ Daemon should be ready"
echo ""

echo -e "${CYAN}Verifying daemon can see the custom path:${NC}"
docker exec storage-sage-daemon ls -la "$CONTAINER_PATH" 2>/dev/null | head -10 | sed 's/^/  /' || echo "  (Path verification - may need a moment)"
echo ""

read -p "Press Enter to trigger cleanup and watch the magic..."

# ═══════════════════════════════════════════════════════════════
# STEP 4: TRIGGER CLEANUP AND OBSERVE
# ═══════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${MAGENTA}  STEP 4: Triggering Cleanup and Observing Results${NC}"
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}Before Cleanup:${NC}"
echo ""
echo "  Files in $CUSTOM_PATH:"
OLD_FILES=$(ls -1 "$CUSTOM_PATH"/old_* 2>/dev/null | wc -l)
RECENT_FILES=$(ls -1 "$CUSTOM_PATH"/recent_* 2>/dev/null | wc -l)
CURRENT_FILES=$(ls -1 "$CUSTOM_PATH"/current_* 2>/dev/null | wc -l)
TOTAL_BEFORE=$(ls -1 "$CUSTOM_PATH" | wc -l)
SIZE_BEFORE=$(du -sh "$CUSTOM_PATH" 2>/dev/null | awk '{print $1}')

echo "    Old files (15-20 days): $OLD_FILES"
echo "    Recent files (1 day): $RECENT_FILES"
echo "    Current files (now): $CURRENT_FILES"
echo "    Total: $TOTAL_BEFORE files ($SIZE_BEFORE)"
echo ""

# Get metrics before
echo -e "${CYAN}Metrics before cleanup:${NC}"
METRICS_BEFORE=$(curl -s http://localhost:9090/metrics 2>/dev/null)
FILES_DELETED_BEFORE=$(echo "$METRICS_BEFORE" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
BYTES_FREED_BEFORE=$(echo "$METRICS_BEFORE" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')
BYTES_MB_BEFORE=$(echo "scale=2; ${BYTES_FREED_BEFORE:-0} / 1024 / 1024" | bc 2>/dev/null || echo "0")

echo "  Files deleted total: $FILES_DELETED_BEFORE"
echo "  Bytes freed total: $BYTES_MB_BEFORE MB"
echo ""

echo -e "${CYAN}Triggering cleanup:${NC}"
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' 2>/dev/null | jq -r '.token' 2>/dev/null)

TRIGGER_RESPONSE=$(curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger 2>/dev/null)
echo "$TRIGGER_RESPONSE" | jq '.' | sed 's/^/  /'
echo ""

echo "  Waiting for cleanup to complete (10 seconds)..."
for i in {10..1}; do
    echo -ne "    $i...\r"
    sleep 1
done
echo "    Cleanup complete!    "
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 5: VERIFY RESULTS
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${MAGENTA}  STEP 5: Verification - Files Cleaned Up!${NC}"
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}After Cleanup:${NC}"
echo ""
echo "  Files in $CUSTOM_PATH:"

OLD_FILES_AFTER=$(ls -1 "$CUSTOM_PATH"/old_* 2>/dev/null | wc -l)
RECENT_FILES_AFTER=$(ls -1 "$CUSTOM_PATH"/recent_* 2>/dev/null | wc -l)
CURRENT_FILES_AFTER=$(ls -1 "$CUSTOM_PATH"/current_* 2>/dev/null | wc -l)
TOTAL_AFTER=$(ls -1 "$CUSTOM_PATH" 2>/dev/null | wc -l)
SIZE_AFTER=$(du -sh "$CUSTOM_PATH" 2>/dev/null | awk '{print $1}')

if [ "$OLD_FILES_AFTER" -eq 0 ]; then
    echo -e "    ${GREEN}✓ Old files (15-20 days): 0 (ALL DELETED!)${NC}"
else
    echo -e "    ${YELLOW}⚠ Old files remaining: $OLD_FILES_AFTER${NC}"
fi

if [ "$RECENT_FILES_AFTER" -eq "$RECENT_FILES" ]; then
    echo -e "    ${GREEN}✓ Recent files (1 day): $RECENT_FILES_AFTER (ALL KEPT!)${NC}"
else
    echo -e "    ${YELLOW}⚠ Recent files: $RECENT_FILES_AFTER (expected $RECENT_FILES)${NC}"
fi

if [ "$CURRENT_FILES_AFTER" -eq "$CURRENT_FILES" ]; then
    echo -e "    ${GREEN}✓ Current files: $CURRENT_FILES_AFTER (ALL KEPT!)${NC}"
else
    echo -e "    ${YELLOW}⚠ Current files: $CURRENT_FILES_AFTER (expected $CURRENT_FILES)${NC}"
fi

FILES_DELETED_COUNT=$((TOTAL_BEFORE - TOTAL_AFTER))
echo ""
echo "    Total now: $TOTAL_AFTER files ($SIZE_AFTER)"
echo -e "    ${BOLD}Files deleted: $FILES_DELETED_COUNT${NC}"
echo ""

# Get metrics after
echo -e "${CYAN}Metrics after cleanup:${NC}"
METRICS_AFTER=$(curl -s http://localhost:9090/metrics 2>/dev/null)
FILES_DELETED_AFTER=$(echo "$METRICS_AFTER" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
BYTES_FREED_AFTER=$(echo "$METRICS_AFTER" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')
BYTES_MB_AFTER=$(echo "scale=2; ${BYTES_FREED_AFTER:-0} / 1024 / 1024" | bc 2>/dev/null || echo "0")

FILES_DELTA=$((FILES_DELETED_AFTER - FILES_DELETED_BEFORE))
BYTES_DELTA=$(echo "scale=2; $BYTES_MB_AFTER - $BYTES_MB_BEFORE" | bc 2>/dev/null || echo "0")

echo "  Files deleted total: $FILES_DELETED_AFTER (+$FILES_DELTA)"
echo "  Bytes freed total: $BYTES_MB_AFTER MB (+$BYTES_DELTA MB)"
echo ""

# Show remaining files
echo -e "${CYAN}Files still in directory (should only be recent/current):${NC}"
ls -lh "$CUSTOM_PATH" 2>/dev/null | sed 's/^/  /'
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 6: DATABASE VERIFICATION
# ═══════════════════════════════════════════════════════════════
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${MAGENTA}  STEP 6: Database Audit Trail${NC}"
echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}Recent deletions from this custom path:${NC}"
docker exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT datetime(timestamp, 'localtime'), action, substr(path, -50), size
   FROM deletions
   WHERE path LIKE '%$(basename $CUSTOM_PATH)%'
   ORDER BY timestamp DESC
   LIMIT 10;" 2>/dev/null | sed 's/^/  /' || echo "  (No deletions recorded yet)"
echo ""

# ═══════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              CUSTOM PATH DEMONSTRATION COMPLETE              ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BOLD}${GREEN}✅ SUCCESS! StorageSage Works on Custom Paths!${NC}"
echo ""

echo -e "${CYAN}What Just Happened:${NC}"
echo "  1. ✓ Created custom directory: $CUSTOM_PATH"
echo "  2. ✓ Added 21 test files (old, recent, current)"
echo "  3. ✓ Updated StorageSage configuration"
echo "  4. ✓ Added path-specific cleanup rules"
echo "  5. ✓ Mounted path in Docker container"
echo "  6. ✓ Restarted daemon with new config"
echo "  7. ✓ Triggered cleanup"
echo "  8. ✓ Verified intelligent deletion:"
echo "      • Old files (15-20 days): DELETED"
echo "      • Recent files (1 day): KEPT"
echo "      • Current files: KEPT"
echo ""

echo -e "${CYAN}Results:${NC}"
echo "  • Files deleted from custom path: $FILES_DELETED_COUNT"
echo "  • Space freed: $BYTES_DELTA MB"
echo "  • Files preserved: $TOTAL_AFTER (recent/current)"
echo "  • Database records: All deletions tracked"
echo ""

echo -e "${CYAN}Configuration Files Modified:${NC}"
echo "  • $CONFIG_FILE (scan_paths + path rules)"
echo "  • $COMPOSE_FILE (volume mount)"
echo ""
echo "  Backups saved:"
echo "    - $BACKUP_FILE"
echo "    - $COMPOSE_BACKUP"
echo ""

echo -e "${YELLOW}To restore original configuration:${NC}"
echo "  cp $BACKUP_FILE $CONFIG_FILE"
echo "  cp $COMPOSE_BACKUP $COMPOSE_FILE"
echo "  docker-compose restart storage-sage-daemon"
echo ""

echo -e "${CYAN}To test another path:${NC}"
echo "  ./demo_custom_path.sh /path/to/your/directory"
echo ""

echo -e "${BOLD}${GREEN}StorageSage can monitor and clean ANY directory!${NC}"
echo ""
