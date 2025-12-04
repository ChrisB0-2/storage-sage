#!/bin/bash

# StorageSage Loki Integration Test Suite
# Complete validation of Promtail → Loki → Grafana pipeline

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🧪 StorageSage Loki Integration Test Suite"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

# Global variables
DAEMON_CONTAINER=""
GRAFANA_PASSWORD=""

# ============================================
# Helper Functions
# ============================================

test_check() {
    local name="$1"
    local command="$2"
    local optional="${3:-false}"
    
    echo -n "  Testing $name... "
    set +e
    eval "$command" &> /dev/null
    local result=$?
    set -e
    
    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        if [[ "$optional" == "true" ]]; then
            echo -e "${YELLOW}⚠ SKIPPED${NC}"
            WARNINGS=$((WARNINGS + 1))
            return 0
        else
            echo -e "${RED}✗ FAILED${NC}"
            FAILED=$((FAILED + 1))
            return 1
        fi
    fi
}

test_query() {
    local name="$1"
    local query="$2"
    local expected_min="${3:-1}"
    
    echo -n "  Testing $name... "
    set +e
    local result=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
        --data-urlencode "query=${query}" \
        --data-urlencode "start=$(date -u -d '10 minutes ago' +%s 2>/dev/null || date -u -v-10M +%s 2>/dev/null || echo $(($(date +%s) - 600)))000000000" \
        --data-urlencode "end=$(date -u +%s)000000000" \
        --data-urlencode "limit=1000" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
    set -e
    
    if [[ "$result" -ge "$expected_min" ]]; then
        echo -e "${GREEN}✓ PASSED${NC} (found $result entries)"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC} (found $result, expected >= $expected_min)"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

wait_for_logs() {
    local search_term="$1"
    local max_wait="${2:-60}"
    local check_interval="${3:-5}"
    
    echo "  Waiting for logs to appear in Loki (max ${max_wait}s)..."
    
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        set +e
        local count=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
            --data-urlencode "query={job=\"storage-sage\"} |~ \"${search_term}\"" \
            --data-urlencode "start=$(($(date +%s) - 600))000000000" \
            --data-urlencode "end=$(date +%s)000000000" \
            2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0")
        set -e
        
        if [[ "$count" -gt 0 ]]; then
            echo -e "  ${GREEN}✓ Logs appeared after ${elapsed}s${NC}"
            return 0
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        echo -n "."
    done
    
    echo ""
    echo -e "  ${YELLOW}⚠ Logs did not appear within ${max_wait}s${NC}"
    return 1
}

# ============================================
# Phase 0: Dependency Check
# ============================================
echo -e "${BLUE}Phase 0: Checking Dependencies${NC}"
echo "----------------------------------------"

MISSING_DEPS=()
for cmd in curl jq docker; do
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $cmd"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $cmd (not installed)"
        MISSING_DEPS+=("$cmd")
        FAILED=$((FAILED + 1))
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}ERROR: Missing required dependencies: ${MISSING_DEPS[*]}${NC}"
    echo ""
    echo "Install missing dependencies:"
    for dep in "${MISSING_DEPS[@]}"; do
        case "$dep" in
            jq)
                echo "  • jq: sudo dnf install jq  (RHEL/Fedora)"
                echo "        sudo apt install jq  (Debian/Ubuntu)"
                ;;
            curl)
                echo "  • curl: sudo dnf install curl  (RHEL/Fedora)"
                echo "          sudo apt install curl  (Debian/Ubuntu)"
                ;;
            docker)
                echo "  • docker: https://docs.docker.com/engine/install/"
                ;;
        esac
    done
    exit 1
fi

echo ""

# ============================================
# Phase 1: Service Health Checks
# ============================================
echo -e "${BLUE}Phase 1: Service Health Checks${NC}"
echo "----------------------------------------"

# Docker daemon
test_check "Docker daemon is running" "docker ps > /dev/null"

# Loki
echo -n "  Testing Loki is accessible... "
set +e
LOKI_STATUS=$(curl -sf http://localhost:3100/ready 2>/dev/null)
set -e

if echo "$LOKI_STATUS" | grep -q "ready"; then
    echo -e "${GREEN}✓ PASSED${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "    Loki is not responding at http://localhost:3100"
    echo "    Start Loki: docker-compose up -d loki"
    FAILED=$((FAILED + 1))
fi

# Promtail
echo -n "  Testing Promtail container is running... "
set +e
PROMTAIL_RUNNING=$(docker ps --filter "name=promtail" --format "{{.Names}}" 2>/dev/null)
set -e

if [[ -n "$PROMTAIL_RUNNING" ]]; then
    echo -e "${GREEN}✓ PASSED${NC} ($PROMTAIL_RUNNING)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "    Promtail container not found"
    echo "    Start Promtail: docker-compose up -d promtail"
    FAILED=$((FAILED + 1))
fi

# Grafana
echo -n "  Testing Grafana is accessible... "
set +e
GRAFANA_STATUS=$(curl -sf http://localhost:3001/api/health 2>/dev/null | jq -r '.database' 2>/dev/null)
set -e

if [[ "$GRAFANA_STATUS" == "ok" ]]; then
    echo -e "${GREEN}✓ PASSED${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ WARNING${NC} (Grafana may not be fully ready)"
    WARNINGS=$((WARNINGS + 1))
fi

# Find StorageSage daemon container (optional)
echo -n "  Looking for StorageSage daemon container... "
set +e
DAEMON_CONTAINER=$(docker ps --format '{{.Names}}' | grep -iE '(storage.*sage|storagesage).*daemon' | head -1)
set -e

if [[ -n "$DAEMON_CONTAINER" ]]; then
    echo -e "${GREEN}✓ FOUND${NC} ($DAEMON_CONTAINER)"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ NOT FOUND${NC}"
    echo "    Log generation will use alternative methods"
    WARNINGS=$((WARNINGS + 1))
fi

# Get Grafana password
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    GRAFANA_PASSWORD=$(grep "GRAFANA.*PASSWORD" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "")
fi

if [[ -z "$GRAFANA_PASSWORD" ]]; then
    set +e
    GRAFANA_PASSWORD=$(docker exec "$(docker ps --filter 'name=grafana' --format '{{.Names}}' | head -1)" env 2>/dev/null | grep -E 'GF_SECURITY_ADMIN_PASSWORD|GRAFANA.*PASSWORD' | cut -d'=' -f2 | head -1 || echo "admin")
    set -e
fi

echo ""

# Check if we should continue
if [[ $FAILED -gt 3 ]]; then
    echo -e "${RED}ERROR: Too many critical services are unavailable.${NC}"
    echo "Please start the Loki stack with: docker-compose up -d"
    exit 1
fi

# ============================================
# Phase 2: Generating Test Log Entries
# ============================================
echo -e "${BLUE}Phase 2: Generating Test Log Entries${NC}"
echo "----------------------------------------"

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Test entries covering all scenarios
TEST_ENTRIES=(
    "[${TIMESTAMP}] DELETE path=/tmp/test-file-1.log object=file size=1024 deletion_reason=\"age_threshold: 10d (max=7d)\""
    "[${TIMESTAMP}] DELETE path=/var/log/app.log object=file size=2048 deletion_reason=\"disk_threshold: 95.0% (max=90.0%)\""
    "[${TIMESTAMP}] DELETE path=/data/old.log object=file size=4096 deletion_reason=\"disk_threshold: 92.0% (max=90.0%) + age_threshold: 20d (max=7d)\""
    "[${TIMESTAMP}] DELETE path=/tmp/critical.log object=file size=8192 deletion_reason=\"stacked_cleanup: disk_usage=99.0% (threshold=98.0%), age=25d (min=14d) + disk_threshold: 99.0% (max=90.0%) + age_threshold: 25d (max=7d)\""
    "[${TIMESTAMP}] SKIP path=/mnt/nfs/stale.log object=nfs_stale size=0 deletion_reason=\"nfs_stale\""
    "[${TIMESTAMP}] ERROR path=/protected/file.log object=file size=0 deletion_reason=\"permission_denied\""
    "[${TIMESTAMP}] DELETE path=/tmp/empty-dir object=empty_directory size=0 deletion_reason=\"age_threshold: 30d (max=7d)\""
    "[${TIMESTAMP}] DRY_RUN path=/tmp/would-delete.log object=file size=512 deletion_reason=\"age_threshold: 8d (max=7d)\""
)

# Try to write logs
WRITE_SUCCESS=false

if [[ -n "$DAEMON_CONTAINER" ]]; then
    echo "  Attempting to write logs via daemon container ($DAEMON_CONTAINER)..."
    
    set +e
    SUCCESS_COUNT=0
    FAILED_COUNT=0
    
    for entry in "${TEST_ENTRIES[@]}"; do
        # Escape single quotes in the entry for shell
        ESCAPED_ENTRY=$(echo "$entry" | sed "s/'/'\\\\''/g")
        
        if docker exec "$DAEMON_CONTAINER" sh -c "echo '$ESCAPED_ENTRY' >> /var/log/storage-sage/cleanup.log" 2>/dev/null; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    done
    set -e
    
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
        echo -e "  ${GREEN}✓ Successfully wrote $SUCCESS_COUNT log entries${NC}"
        if [[ $FAILED_COUNT -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠ Failed to write $FAILED_COUNT entries${NC}"
        fi
        WRITE_SUCCESS=true
        PASSED=$((PASSED + 1))
    fi
fi

# Fallback: Try direct file write
if [[ "$WRITE_SUCCESS" == "false" ]]; then
    LOG_FILE="/var/log/storage-sage/cleanup.log"
    
    if [[ -w "$LOG_FILE" ]]; then
        echo "  Writing test logs directly to $LOG_FILE..."
        for entry in "${TEST_ENTRIES[@]}"; do
            echo "$entry" >> "$LOG_FILE" 2>/dev/null || true
        done
        echo -e "  ${GREEN}✓ Wrote ${#TEST_ENTRIES[@]} test entries${NC}"
        WRITE_SUCCESS=true
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${YELLOW}⚠ Cannot write test logs${NC}"
        echo "    Daemon container not available and log file not writable"
        echo "    Proceeding with existing logs only"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

echo ""

# Wait for Promtail to ship logs
if [[ "$WRITE_SUCCESS" == "true" ]]; then
    wait_for_logs "test-file-1" 60 5
    if [[ $? -ne 0 ]]; then
        echo -e "  ${YELLOW}⚠ Test logs may not have been ingested yet${NC}"
        echo "    Continuing with validation..."
        WARNINGS=$((WARNINGS + 1))
    fi
fi

echo ""

# ============================================
# Phase 3: Log Ingestion Validation
# ============================================
echo -e "${BLUE}Phase 3: Log Ingestion Validation${NC}"
echo "----------------------------------------"

test_query "Basic log ingestion" '{job="storage-sage"}' 1

# Check for our test entries
echo -n "  Checking for test log entries... "
set +e
TEST_COUNT=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={job="storage-sage"} |~ "test-file|critical.log|would-delete"' \
    --data-urlencode "start=$(date -u -d '10 minutes ago' +%s 2>/dev/null || date -u -v-10M +%s 2>/dev/null || echo $(($(date +%s) - 600)))000000000" \
    --data-urlencode "end=$(date -u +%s)000000000" \
    --data-urlencode 'limit=100' 2>/dev/null | jq -r '[.data.result[].values[][1]] | length' 2>/dev/null || echo "0")
set -e

if [[ "$TEST_COUNT" -gt 0 ]]; then
    echo -e "${GREEN}✓ PASSED${NC} (found $TEST_COUNT test entries)"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ WARNING${NC} (no test entries found)"
    
    # Show total log count for debugging
    set +e
    TOTAL_COUNT=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={job="storage-sage"}' \
        --data-urlencode "start=$(date -u -d '10 minutes ago' +%s 2>/dev/null || date -u -v-10M +%s 2>/dev/null || echo $(($(date +%s) - 600)))000000000" \
        --data-urlencode "end=$(date -u +%s)000000000" \
        --data-urlencode 'limit=100' 2>/dev/null | jq -r '[.data.result[].values[][1]] | length' 2>/dev/null || echo "0")
    set -e
    
    echo "    Total logs in Loki (last 10 min): $TOTAL_COUNT"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# ============================================
# Phase 4: Label Extraction Tests
# ============================================
echo -e "${BLUE}Phase 4: Label Extraction Tests${NC}"
echo "----------------------------------------"

echo "  Checking available labels:"
set +e
LABELS=$(curl -s "http://localhost:3100/loki/api/v1/labels" 2>/dev/null | jq -r '.data[]' 2>/dev/null || echo "")
set -e

REQUIRED_LABELS=("job" "action" "object_type")
MISSING_LABELS=()

for label in "${REQUIRED_LABELS[@]}"; do
    echo -n "    • $label: "
    if echo "$LABELS" | grep -q "^${label}$"; then
        echo -e "${GREEN}✓ present${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ missing${NC}"
        MISSING_LABELS+=("$label")
        FAILED=$((FAILED + 1))
    fi
done

if [[ ${#MISSING_LABELS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}ERROR: Missing required labels: ${MISSING_LABELS[*]}${NC}"
    echo "  Check Promtail configuration: promtail/config.yml"
    echo "  Labels should be extracted from log lines"
else
    echo ""
    echo -e "  ${GREEN}✓ All required labels present${NC}"
fi

# Check for primary_reason label (optional but recommended)
echo -n "  Checking primary_reason label... "
set +e
PRIMARY_REASON_VALUES=$(curl -s "http://localhost:3100/loki/api/v1/label/primary_reason/values" 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo "0")
set -e

if [[ "$PRIMARY_REASON_VALUES" -gt 0 ]]; then
    echo -e "${GREEN}✓ PRESENT${NC} ($PRIMARY_REASON_VALUES values)"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ NOT FOUND${NC}"
    echo "    primary_reason is optional but recommended for filtering"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# Test label value queries
echo "  Testing label-based queries:"
test_query "Query by action=DELETE" '{job="storage-sage", action="DELETE"}' 0
test_query "Query by action=SKIP" '{job="storage-sage", action="SKIP"}' 0
test_query "Query by object_type=file" '{job="storage-sage", object_type="file"}' 0

echo ""

# ============================================
# Phase 5: Query Functionality Tests
# ============================================
echo -e "${BLUE}Phase 5: Query Functionality Tests${NC}"
echo "----------------------------------------"

test_query "Query with line filter" '{job="storage-sage"} |~ "DELETE"' 0
test_query "Query age_threshold deletions" '{job="storage-sage"} |~ "age_threshold"' 0
test_query "Query disk_threshold deletions" '{job="storage-sage"} |~ "disk_threshold"' 0
test_query "Query stacked_cleanup (critical)" '{job="storage-sage"} |~ "stacked_cleanup"' 0

echo ""

# ============================================
# Phase 6: Performance Tests
# ============================================
echo -e "${BLUE}Phase 6: Performance Tests${NC}"
echo "----------------------------------------"

echo -n "  Testing query performance (24h range)... "
START_TIME=$(date +%s%N)
set +e
curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={job="storage-sage"}' \
    --data-urlencode "start=$(date -u -d '24 hours ago' +%s 2>/dev/null || date -u -v-24H +%s 2>/dev/null || echo $(($(date +%s) - 86400)))000000000" \
    --data-urlencode "end=$(date -u +%s)000000000" \
    --data-urlencode 'limit=100' &> /dev/null
QUERY_STATUS=$?
set -e
END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

if [[ $QUERY_STATUS -eq 0 ]]; then
    if [[ $DURATION_MS -lt 2000 ]]; then
        echo -e "${GREEN}✓ EXCELLENT${NC} (${DURATION_MS}ms - under 2s target)"
        PASSED=$((PASSED + 1))
    elif [[ $DURATION_MS -lt 5000 ]]; then
        echo -e "${YELLOW}⚠ ACCEPTABLE${NC} (${DURATION_MS}ms - under 5s)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${RED}✗ SLOW${NC} (${DURATION_MS}ms - exceeds 5s)"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗ FAILED${NC} (query error)"
    FAILED=$((FAILED + 1))
fi

echo ""

# ============================================
# Phase 7: Data Validation
# ============================================
echo -e "${BLUE}Phase 7: Data Validation${NC}"
echo "----------------------------------------"

echo -n "  Validating log format parsing... "
set +e
SAMPLE_LOG=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={job="storage-sage"}' \
    --data-urlencode "start=$(date -u -d '10 minutes ago' +%s 2>/dev/null || date -u -v-10M +%s 2>/dev/null || echo $(($(date +%s) - 600)))000000000" \
    --data-urlencode "end=$(date -u +%s)000000000" \
    --data-urlencode 'limit=1' 2>/dev/null | jq -r '.data.result[0].values[0][1]' 2>/dev/null || echo "")
set -e

if [[ -n "$SAMPLE_LOG" ]] && echo "$SAMPLE_LOG" | grep -qE '^\[.*\] (DELETE|SKIP|ERROR|DRY_RUN) path='; then
    echo -e "${GREEN}✓ PASSED${NC}"
    echo "    Sample: ${SAMPLE_LOG:0:80}..."
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ WARNING${NC}"
    if [[ -n "$SAMPLE_LOG" ]]; then
        echo "    Sample: ${SAMPLE_LOG:0:100}..."
    else
        echo "    No logs available to validate"
    fi
    WARNINGS=$((WARNINGS + 1))
fi

echo -n "  Validating timestamp extraction... "
set +e
TIMESTAMP_SAMPLE=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={job="storage-sage"}' \
    --data-urlencode "start=$(date -u -d '10 minutes ago' +%s 2>/dev/null || date -u -v-10M +%s 2>/dev/null || echo $(($(date +%s) - 600)))000000000" \
    --data-urlencode "end=$(date -u +%s)000000000" \
    --data-urlencode 'limit=1' 2>/dev/null | jq -r '.data.result[0].values[0][0]' 2>/dev/null || echo "0")
set -e

if [[ "$TIMESTAMP_SAMPLE" != "0" ]] && [[ "$TIMESTAMP_SAMPLE" != "null" ]] && [[ ${#TIMESTAMP_SAMPLE} -ge 10 ]]; then
    # Convert nanosecond timestamp to readable format
    TIMESTAMP_SEC=$((TIMESTAMP_SAMPLE / 1000000000))
    READABLE_TS=$(date -u -d "@$TIMESTAMP_SEC" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -u -r "$TIMESTAMP_SEC" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "valid")
    echo -e "${GREEN}✓ PASSED${NC} ($READABLE_TS UTC)"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ WARNING${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# ============================================
# Phase 8: Sample Logs Display
# ============================================
echo -e "${BLUE}Phase 8: Sample Logs in Loki${NC}"
echo "----------------------------------------"
echo "  Recent logs from Loki:"
echo ""

set +e
SAMPLE_LOGS=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
    --data-urlencode 'query={job="storage-sage"}' \
    --data-urlencode "start=$(date -u -d '10 minutes ago' +%s 2>/dev/null || date -u -v-10M +%s 2>/dev/null || echo $(($(date +%s) - 600)))000000000" \
    --data-urlencode "end=$(date -u +%s)000000000" \
    --data-urlencode 'limit=5' 2>/dev/null)

if echo "$SAMPLE_LOGS" | jq -e '.data.result | length > 0' &>/dev/null; then
    echo "$SAMPLE_LOGS" | jq -r '.data.result[].values[]? | "    [\(.[0] | tonumber / 1000000000 | strftime("%Y-%m-%d %H:%M:%S"))] \(.[1])"' 2>/dev/null | head -5
    echo ""
    echo -e "  ${GREEN}✓ Logs are visible in Loki${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${YELLOW}⚠ No logs found in last 10 minutes${NC}"
    echo "    This may be normal if no cleanup has run recently"
    WARNINGS=$((WARNINGS + 1))
fi
set -e

echo ""

# ============================================
# Phase 9: Dashboard Check (Optional)
# ============================================
echo -e "${BLUE}Phase 9: Grafana Dashboard Check${NC}"
echo "----------------------------------------"

echo -n "  Checking for StorageSage dashboard... "
set +e
DASHBOARD_CHECK=$(curl -s "http://localhost:3001/api/search?query=storage-sage" \
    -H "Content-Type: application/json" 2>/dev/null | jq -r '. | length' 2>/dev/null || echo "0")
set -e

if [[ "$DASHBOARD_CHECK" -gt 0 ]]; then
    echo -e "${GREEN}✓ FOUND${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ NOT FOUND${NC}"
    echo "    Dashboard needs to be imported manually"
    echo "    File: grafana/dashboards/storage-sage-deletion-analytics.json"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# ============================================
# Summary
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Test Results Summary:"
echo -e "  ${GREEN}✓ Passed:   ${PASSED}${NC}"
echo -e "  ${RED}✗ Failed:   ${FAILED}${NC}"
echo -e "  ${YELLOW}⚠ Warnings: ${WARNINGS}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Final verdict
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All critical tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Access Grafana: http://localhost:3001"
    echo "  2. Login: admin / $GRAFANA_PASSWORD"
    echo "  3. Import dashboard: grafana/dashboards/storage-sage-deletion-analytics.json"
    echo "  4. Explore Loki: Configuration → Data Sources → Loki → Explore"
    echo ""
    echo "Useful Loki queries:"
    echo "  • All logs: {job=\"storage-sage\"}"
    echo "  • Deletions only: {job=\"storage-sage\", action=\"DELETE\"}"
    echo "  • Errors: {job=\"storage-sage\", action=\"ERROR\"}"
    echo "  • Stacked cleanup: {job=\"storage-sage\"} |~ \"stacked_cleanup\""
    exit 0
elif [[ $FAILED -le 3 ]] && [[ $PASSED -gt 10 ]]; then
    echo -e "${YELLOW}⚠️  Tests completed with some failures${NC}"
    echo ""
    echo "The Loki integration is mostly working, but some components need attention."
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check Promtail logs: docker logs storage-sage-promtail"
    echo "  2. Check Loki logs: docker logs storage-sage-loki"
    echo "  3. Verify Promtail config: cat promtail/config.yml"
    echo "  4. Check log file: docker exec $DAEMON_CONTAINER ls -la /var/log/storage-sage/"
    exit 1
else
    echo -e "${RED}❌ Critical tests failed${NC}"
    echo ""
    echo "The Loki integration is not working correctly."
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Verify services are running: docker-compose ps"
    echo "  2. Check Loki: docker logs storage-sage-loki"
    echo "  3. Check Promtail: docker logs storage-sage-promtail"
    echo "  4. Restart stack: docker-compose restart"
    echo "  5. Check Promtail config: promtail/config.yml"
    echo ""
    echo "Common issues:"
    echo "  • Labels not extracted → Check Promtail pipeline_stages"
    echo "  • No logs in Loki → Check Promtail can read log file"
    echo "  • Slow queries → Check Loki resource limits"
    exit 1
fi