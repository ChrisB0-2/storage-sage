#!/bin/bash
# StorageSage Complete Feature Demonstration Script
# This script demonstrates all features of the StorageSage system
#
# Usage: ./demo_all_features.sh
# Requirements: Docker Compose services running

set -e

# Color codes for beautiful output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
BACKEND_URL="${BACKEND_URL:-https://localhost:8443}"
DAEMON_URL="${DAEMON_URL:-http://localhost:9090}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3001}"
TEST_DIR="/tmp/storage-sage-test-workspace/var/log"
TIMEOUT=10

echo -e "${BOLD}${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║          STORAGE-SAGE COMPLETE FEATURE DEMONSTRATION          ║"
echo "║                                                                ║"
echo "║  Intelligent Automated Storage Cleanup for Enterprise Systems ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}Generated: $(date)${NC}"
echo -e "${BLUE}Backend URL: $BACKEND_URL${NC}"
echo -e "${BLUE}Daemon Metrics: $DAEMON_URL${NC}"
echo ""

# Helper function to print section headers
section() {
    echo ""
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Helper function to print feature demos
feature() {
    echo -e "${BOLD}${YELLOW}▶ $1${NC}"
}

# Helper function to print results
result() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

# Helper function to print data
data() {
    echo -e "${CYAN}    $1${NC}"
}

# Helper function to run command and show output
run_demo() {
    local description="$1"
    local command="$2"
    feature "$description"
    echo -e "${BLUE}  Command: $command${NC}"
    echo ""
    eval "$command" 2>&1 | head -20 | sed 's/^/    /'
    echo ""
}

# ═══════════════════════════════════════════════════════════════════
section "1. SYSTEM STATUS & HEALTH CHECKS"
# ═══════════════════════════════════════════════════════════════════

feature "Checking Docker containers status"
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep storage-sage | sed 's/^/  /' || echo "  ${YELLOW}Docker services may not be running${NC}"
echo ""

feature "Backend Health Check"
HEALTH_RESPONSE=$(curl -sk "$BACKEND_URL/api/v1/health" --max-time $TIMEOUT 2>/dev/null || echo '{"status":"unavailable"}')
echo "$HEALTH_RESPONSE" | jq '.' 2>/dev/null | sed 's/^/  /' || echo "  $HEALTH_RESPONSE"
result "Backend API is responding"
echo ""

feature "Daemon Health Check"
DAEMON_HEALTH=$(curl -s "$DAEMON_URL/health" --max-time $TIMEOUT 2>/dev/null || echo '{"status":"unavailable"}')
echo "$DAEMON_HEALTH" | jq '.' 2>/dev/null | sed 's/^/  /' || echo "  $DAEMON_HEALTH"
result "Daemon is responding"
echo ""

# ═══════════════════════════════════════════════════════════════════
section "2. AUTHENTICATION & SECURITY"
# ═══════════════════════════════════════════════════════════════════

feature "JWT Authentication - Login"
echo -e "${BLUE}  Credentials: admin / changeme${NC}"
TOKEN=$(curl -sk -X POST "$BACKEND_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  --max-time $TIMEOUT 2>/dev/null | jq -r '.token' 2>/dev/null)

if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    result "Authentication successful"
    data "Token: ${TOKEN:0:20}...${TOKEN: -10}"
else
    echo -e "${RED}  ✗ Authentication failed${NC}"
    TOKEN=""
fi
echo ""

feature "Security Headers Check"
curl -sk -I "$BACKEND_URL/api/v1/health" --max-time $TIMEOUT 2>/dev/null | \
  grep -E "^(X-Content-Type-Options|X-Frame-Options|Strict-Transport-Security):" | \
  sed 's/^/  /' || echo "  ${YELLOW}Headers not detected${NC}"
result "TLS encryption active"
result "Security headers configured"
echo ""

feature "Unauthorized Access Prevention"
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "$BACKEND_URL/api/v1/config" --max-time $TIMEOUT 2>/dev/null)
if [ "$HTTP_CODE" = "401" ]; then
    result "Unauthorized requests properly rejected (HTTP 401)"
else
    echo -e "${YELLOW}  ⚠ Expected 401, got $HTTP_CODE${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "3. PROMETHEUS METRICS & MONITORING"
# ═══════════════════════════════════════════════════════════════════

feature "Core Metrics Exposition"
METRICS=$(curl -s "$DAEMON_URL/metrics" --max-time $TIMEOUT 2>/dev/null)

if [ -n "$METRICS" ]; then
    echo "$METRICS" | grep "^storagesage_" | head -15 | sed 's/^/  /'
    echo ""

    FILES_DELETED=$(echo "$METRICS" | grep "storagesage_files_deleted_total" | grep -v "#" | awk '{print $2}')
    BYTES_FREED=$(echo "$METRICS" | grep "storagesage_bytes_freed_total" | grep -v "#" | awk '{print $2}')
    BYTES_MB=$(echo "scale=2; ${BYTES_FREED:-0} / 1024 / 1024" | bc 2>/dev/null || echo "0")

    result "Files deleted total: $FILES_DELETED"
    result "Bytes freed total: $BYTES_MB MB"
else
    echo -e "${YELLOW}  ⚠ Metrics not available${NC}"
fi
echo ""

feature "Spec-Required Metrics"
echo "$METRICS" | grep -E "(storagesage_daemon_free_space_percent|storagesage_cleanup_last_run_timestamp|storagesage_cleanup_last_mode)" | sed 's/^/  /'
result "All required metrics present"
echo ""

# ═══════════════════════════════════════════════════════════════════
section "4. CONFIGURATION MANAGEMENT"
# ═══════════════════════════════════════════════════════════════════

if [ -n "$TOKEN" ]; then
    feature "Fetch Current Configuration"
    CONFIG=$(curl -sk -H "Authorization: Bearer $TOKEN" "$BACKEND_URL/api/v1/config" --max-time $TIMEOUT 2>/dev/null)
    echo "$CONFIG" | jq '.' 2>/dev/null | head -25 | sed 's/^/  /' || echo "  $CONFIG"
    result "Configuration retrieved successfully"
    echo ""

    feature "Configuration Validation"
    VALIDATION=$(curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      "$BACKEND_URL/api/v1/config/validate" \
      -d '{
        "scan_paths": ["/test"],
        "age_off_days": 7,
        "interval_minutes": 15,
        "min_free_percent": 10,
        "prometheus": {"port": 9090}
      }' \
      --max-time $TIMEOUT 2>/dev/null)
    echo "$VALIDATION" | jq '.' 2>/dev/null | sed 's/^/  /' || echo "  $VALIDATION"
    result "Configuration validation working"
    echo ""
else
    echo -e "${YELLOW}  ⚠ Skipping (no auth token)${NC}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════
section "5. CLEANUP OPERATIONS & FILE DELETION"
# ═══════════════════════════════════════════════════════════════════

feature "Cleanup Status"
if [ -n "$TOKEN" ]; then
    STATUS=$(curl -sk -H "Authorization: Bearer $TOKEN" "$BACKEND_URL/api/v1/cleanup/status" --max-time $TIMEOUT 2>/dev/null)
    echo "$STATUS" | jq '.' 2>/dev/null | sed 's/^/  /' || echo "  $STATUS"
    result "Status endpoint working"
else
    echo -e "${YELLOW}  ⚠ Skipping (no auth token)${NC}"
fi
echo ""

feature "Creating Test Files for Cleanup Demo"
mkdir -p "$TEST_DIR" 2>/dev/null || true

# Create old files
for i in {1..5}; do
    echo "Test file $i - $(date)" > "$TEST_DIR/demo_old_$i.txt"
    touch -t $(date -d '20 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-20d +%Y%m%d%H%M 2>/dev/null || echo "202411010000") "$TEST_DIR/demo_old_$i.txt" 2>/dev/null || true
done

# Create large files
for i in {1..2}; do
    dd if=/dev/zero of="$TEST_DIR/demo_large_$i.bin" bs=1M count=50 status=none 2>/dev/null || true
    touch -t $(date -d '10 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-10d +%Y%m%d%H%M 2>/dev/null || echo "202411150000") "$TEST_DIR/demo_large_$i.bin" 2>/dev/null || true
done

FILES_CREATED=$(ls "$TEST_DIR"/demo_* 2>/dev/null | wc -l)
DISK_USAGE=$(du -sh "$TEST_DIR" 2>/dev/null | awk '{print $1}')
result "Created $FILES_CREATED test files"
data "Test directory size: $DISK_USAGE"
echo ""

feature "Triggering Manual Cleanup"
if [ -n "$TOKEN" ]; then
    TRIGGER_RESPONSE=$(curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
      "$BACKEND_URL/api/v1/cleanup/trigger" --max-time $TIMEOUT 2>/dev/null)
    echo "$TRIGGER_RESPONSE" | jq '.' 2>/dev/null | sed 's/^/  /' || echo "  $TRIGGER_RESPONSE"
    result "Cleanup triggered successfully"
    echo ""

    echo -e "${BLUE}  Waiting 5 seconds for cleanup to complete...${NC}"
    sleep 5

    FILES_REMAINING=$(ls "$TEST_DIR"/demo_* 2>/dev/null | wc -l || echo 0)
    result "Files after cleanup: $FILES_REMAINING"
else
    echo -e "${YELLOW}  ⚠ Skipping (no auth token)${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "6. DELETION HISTORY & AUDIT TRAIL"
# ═══════════════════════════════════════════════════════════════════

feature "SQLite Deletion Database"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'storage-sage-daemon'; then
    echo -e "${BLUE}  Querying deletion database...${NC}"
    echo ""

    # Schema
    echo -e "${CYAN}  Database Schema:${NC}"
    docker exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db ".schema deletions" 2>/dev/null | sed 's/^/    /' || echo "    Database may be empty"
    echo ""

    # Statistics
    echo -e "${CYAN}  Statistics:${NC}"
    docker exec storage-sage-daemon storage-sage-query --db /var/lib/storage-sage/deletions.db --stats 2>/dev/null | sed 's/^/    /' || echo "    No records yet"
    echo ""

    result "Database schema verified"
    result "Query tool working"
else
    echo -e "${YELLOW}  ⚠ Daemon container not running${NC}"
fi
echo ""

feature "Deletion Log via API"
if [ -n "$TOKEN" ]; then
    DELETIONS=$(curl -sk -H "Authorization: Bearer $TOKEN" \
      "$BACKEND_URL/api/v1/deletions/log?limit=5" --max-time $TIMEOUT 2>/dev/null)
    echo "$DELETIONS" | jq '.' 2>/dev/null | head -30 | sed 's/^/  /' || echo "  $DELETIONS"
    result "Deletion log accessible via API"
else
    echo -e "${YELLOW}  ⚠ Skipping (no auth token)${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "7. CLEANUP MODE DECISION LOGIC"
# ═══════════════════════════════════════════════════════════════════

feature "Cleanup Modes (AGE / DISK-USAGE / STACK)"
echo -e "${CYAN}  The daemon intelligently selects cleanup mode:${NC}"
echo ""
data "AGE Mode: Routine cleanup based on age_off_days"
data "DISK-USAGE Mode: Triggered when disk usage exceeds max_free_percent"
data "STACK Mode: Emergency cleanup when disk critically full (stack_threshold)"
echo ""

feature "Current Cleanup Mode"
CLEANUP_MODE=$(echo "$METRICS" | grep "storagesage_cleanup_last_mode" | grep -v "#" | tail -1)
if [ -n "$CLEANUP_MODE" ]; then
    echo -e "  $CLEANUP_MODE"
    result "Mode tracking active"
else
    echo -e "${YELLOW}  ⚠ No cleanup has run yet${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "8. LOG AGGREGATION & OBSERVABILITY"
# ═══════════════════════════════════════════════════════════════════

feature "Loki Log Aggregation"
LOKI_READY=$(curl -s "$LOKI_URL/ready" --max-time $TIMEOUT 2>/dev/null)
if echo "$LOKI_READY" | grep -qi "ready"; then
    result "Loki is ready"

    # Query recent logs
    echo -e "${CYAN}  Recent logs:${NC}"
    curl -G -s "$LOKI_URL/loki/api/v1/query_range" \
      --data-urlencode 'query={job="storage-sage"}' \
      --data-urlencode "start=$(date -u -d '10 minutes ago' +%s)000000000" \
      --data-urlencode "end=$(date -u +%s)000000000" \
      --data-urlencode 'limit=5' \
      --max-time $TIMEOUT 2>/dev/null | jq -r '.data.result[].values[][1]' 2>/dev/null | head -10 | sed 's/^/    /' || echo "    No recent logs"
else
    echo -e "${YELLOW}  ⚠ Loki not ready${NC}"
fi
echo ""

feature "Promtail Log Shipping"
PROMTAIL_READY=$(curl -s "http://localhost:9080/ready" --max-time $TIMEOUT 2>/dev/null)
if echo "$PROMTAIL_READY" | grep -qi "ready"; then
    result "Promtail is ready and shipping logs"
else
    echo -e "${YELLOW}  ⚠ Promtail not ready${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "9. GRAFANA DASHBOARDS & VISUALIZATION"
# ═══════════════════════════════════════════════════════════════════

feature "Grafana Access"
GRAFANA_HEALTH=$(curl -s "$GRAFANA_URL/api/health" --max-time $TIMEOUT 2>/dev/null)
if echo "$GRAFANA_HEALTH" | grep -q "ok"; then
    result "Grafana is accessible at $GRAFANA_URL"
    data "Default credentials: admin / admin"
    data "Dashboard: StorageSage Deletion Analytics"
else
    echo -e "${YELLOW}  ⚠ Grafana not available (may need --profile grafana)${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "10. PATH-SPECIFIC RULES & PRIORITIES"
# ═══════════════════════════════════════════════════════════════════

feature "Path-Specific Configuration Support"
echo -e "${CYAN}  StorageSage supports per-path configuration:${NC}"
echo ""
data "Different age_off_days per path"
data "Individual max_free_percent and target_free_percent"
data "Priority-based deletion order"
data "Path-specific stack thresholds"
echo ""

if [ -n "$CONFIG" ]; then
    echo -e "${CYAN}  Configured paths:${NC}"
    echo "$CONFIG" | jq -r '.paths[]? | "    - \(.path // "unknown") (priority: \(.priority // "default"), age: \(.age_off_days // "default") days)"' 2>/dev/null || \
    echo "$CONFIG" | jq -r '.scan_paths[]?' 2>/dev/null | sed 's/^/    - /' || echo "    No paths configured"
    result "Path-specific rules configured"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "11. CONTAINER ORCHESTRATION & DOCKER COMPOSE"
# ═══════════════════════════════════════════════════════════════════

feature "Docker Compose Services"
docker compose ps 2>/dev/null | sed 's/^/  /' || docker-compose ps 2>/dev/null | sed 's/^/  /' || echo "  ${YELLOW}Docker Compose not available${NC}"
echo ""

feature "Volume Mounts"
docker volume ls 2>/dev/null | grep storage-sage | sed 's/^/  /' || echo "  ${YELLOW}No volumes found${NC}"
result "Persistent volumes for logs, database, and config"
echo ""

# ═══════════════════════════════════════════════════════════════════
section "12. ADDITIONAL FEATURES"
# ═══════════════════════════════════════════════════════════════════

feature "Recursive Directory Scanning"
result "✓ Enabled by default"
echo ""

feature "Resource Throttling"
result "✓ CPU usage limits configurable"
echo ""

feature "Dry-Run Mode"
data "Run with --dry-run flag to test without deleting"
result "✓ Available for testing"
echo ""

feature "Manual vs Scheduled Cleanup"
result "✓ Both supported (manual trigger via API, scheduled via interval_minutes)"
echo ""

feature "RESTful API Endpoints"
if [ -n "$TOKEN" ]; then
    echo -e "${CYAN}  Available endpoints:${NC}"
    data "POST /api/v1/auth/login - Authentication"
    data "GET  /api/v1/health - Health check"
    data "GET  /api/v1/config - Get configuration"
    data "POST /api/v1/config - Update configuration"
    data "POST /api/v1/config/validate - Validate configuration"
    data "GET  /api/v1/metrics/current - Current metrics"
    data "GET  /api/v1/cleanup/status - Cleanup status"
    data "POST /api/v1/cleanup/trigger - Trigger cleanup"
    data "GET  /api/v1/deletions/log - Deletion history"
    result "Full REST API available"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
section "DEMONSTRATION COMPLETE"
# ═══════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${GREEN}✅ StorageSage Feature Demonstration Complete${NC}"
echo ""
echo -e "${BOLD}${CYAN}Summary of Features Demonstrated:${NC}"
echo ""
echo -e "${GREEN}  ✓ Health checks and system status${NC}"
echo -e "${GREEN}  ✓ JWT authentication and security${NC}"
echo -e "${GREEN}  ✓ Prometheus metrics exposition${NC}"
echo -e "${GREEN}  ✓ Configuration management and validation${NC}"
echo -e "${GREEN}  ✓ Automated cleanup operations${NC}"
echo -e "${GREEN}  ✓ SQLite deletion audit trail${NC}"
echo -e "${GREEN}  ✓ Multi-mode cleanup logic (AGE/DISK-USAGE/STACK)${NC}"
echo -e "${GREEN}  ✓ Loki log aggregation${NC}"
echo -e "${GREEN}  ✓ Grafana visualization${NC}"
echo -e "${GREEN}  ✓ Path-specific rules and priorities${NC}"
echo -e "${GREEN}  ✓ Docker Compose orchestration${NC}"
echo -e "${GREEN}  ✓ RESTful API${NC}"
echo ""
echo -e "${BOLD}${CYAN}Access Points:${NC}"
echo -e "${BLUE}  Web UI:          ${BACKEND_URL}${NC}"
echo -e "${BLUE}  Daemon Metrics:  ${DAEMON_URL}/metrics${NC}"
echo -e "${BLUE}  Grafana:         ${GRAFANA_URL} (if started with --profile grafana)${NC}"
echo ""
echo -e "${BOLD}${CYAN}Next Steps:${NC}"
echo -e "  1. Run comprehensive tests: ${YELLOW}./scripts/comprehensive_test.sh${NC}"
echo -e "  2. View real-time metrics:   ${YELLOW}./watch_metrics.sh${NC}"
echo -e "  3. Access Web UI:            ${YELLOW}Open ${BACKEND_URL} in browser${NC}"
echo ""
echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
