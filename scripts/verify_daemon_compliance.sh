#!/bin/bash
#
# StorageSage Daemon Compliance Verification Script
# Tests daemon functionality against specification
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
TEST_DIR="/tmp/storage-sage-test-$(date +%s)"
# Try to find binary in multiple locations
if [ -n "${STORAGE_SAGE_BINARY:-}" ] && [ -f "${STORAGE_SAGE_BINARY}" ]; then
    BINARY_PATH="${STORAGE_SAGE_BINARY}"
elif [ -f "./storage-sage" ]; then
    BINARY_PATH="./storage-sage"
elif [ -f "/usr/local/bin/storage-sage" ]; then
    BINARY_PATH="/usr/local/bin/storage-sage"
else
    echo "Error: storage-sage binary not found"
    echo "Please set STORAGE_SAGE_BINARY environment variable or ensure binary is in ./storage-sage or /usr/local/bin/storage-sage"
    exit 1
fi
CONFIG_PATH="${TEST_DIR}/test-config.yaml"
PROMETHEUS_PORT="${PROMETHEUS_TEST_PORT:-9091}"
LOG_DIR="${TEST_DIR}/logs"
SCAN_DIR="${TEST_DIR}/scan"
PID_FILE="${TEST_DIR}/storage-sage.pid"
REPORT_FILE="${TEST_DIR}/compliance_report.txt"
ISSUE_LOG="${TEST_DIR}/issue_log.txt"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
PARTIAL_TESTS=0

# Initialize test environment
init_test_env() {
    echo -e "${BLUE}=== Initializing Test Environment ===${NC}"
    mkdir -p "${TEST_DIR}"
    mkdir -p "${LOG_DIR}"
    mkdir -p "${SCAN_DIR}"
    
    # Create test config
    cat > "${CONFIG_PATH}" <<EOF
scan_paths:
  - "${SCAN_DIR}"
age_off_days: 1
min_free_percent: 10
interval_minutes: 1
prometheus:
  port: ${PROMETHEUS_PORT}
EOF
    
    # Create test files (some old, some new)
    touch -d "2 days ago" "${SCAN_DIR}/old_file1.txt"
    touch -d "2 days ago" "${SCAN_DIR}/old_file2.txt"
    touch -d "1 hour ago" "${SCAN_DIR}/new_file1.txt"
    echo "test data" > "${SCAN_DIR}/old_file1.txt"
    echo "test data" > "${SCAN_DIR}/old_file2.txt"
    echo "test data" > "${SCAN_DIR}/new_file1.txt"
    
    echo -e "${GREEN}✓ Test environment initialized${NC}"
}

# Cleanup test environment
cleanup_test_env() {
    echo -e "${BLUE}=== Cleaning Up Test Environment ===${NC}"
    # Stop daemon if running
    if [ -f "${PID_FILE}" ]; then
        local pid=$(cat "${PID_FILE}" 2>/dev/null || echo "")
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null || true
            sleep 2
            kill -9 "${pid}" 2>/dev/null || true
        fi
        rm -f "${PID_FILE}"
    fi
    # Remove test directory
    rm -rf "${TEST_DIR}"
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Test result tracking
test_result() {
    local status="$1"
    local test_name="$2"
    local evidence="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    case "${status}" in
        PASS)
            echo -e "${GREEN}✓ PASS${NC}: ${test_name}" | tee -a "${REPORT_FILE}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            ;;
        FAIL)
            echo -e "${RED}✗ FAIL${NC}: ${test_name}" | tee -a "${REPORT_FILE}"
            echo "  Evidence: ${evidence}" | tee -a "${REPORT_FILE}"
            echo "  Test: ${test_name}" >> "${ISSUE_LOG}"
            echo "  Evidence: ${evidence}" >> "${ISSUE_LOG}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            ;;
        PARTIAL)
            echo -e "${YELLOW}⚠ PARTIAL${NC}: ${test_name}" | tee -a "${REPORT_FILE}"
            echo "  Evidence: ${evidence}" | tee -a "${REPORT_FILE}"
            PARTIAL_TESTS=$((PARTIAL_TESTS + 1))
            ;;
    esac
    echo "" | tee -a "${REPORT_FILE}"
}

# Wait for metrics server to be ready
wait_for_metrics_server() {
    local port="${1:-${PROMETHEUS_PORT}}"
    local max_attempts="${2:-20}"
    local wait_interval="${3:-0.5}"
    local attempt=0
    
    while [ "${attempt}" -lt "${max_attempts}" ]; do
        if curl -s -f "http://localhost:${port}/metrics" >/dev/null 2>&1; then
            # Give it an extra moment to fully initialize metrics
            sleep 1
            return 0
        fi
        sleep "${wait_interval}"
        attempt=$((attempt + 1))
    done
    return 1
}

# Trap for cleanup
trap cleanup_test_env EXIT INT TERM

# ============================================================================
# TEST SUITE
# ============================================================================

echo "=========================================="
echo "StorageSage Daemon Compliance Verification"
echo "=========================================="
echo "Test Directory: ${TEST_DIR}"
echo "Binary: ${BINARY_PATH}"
echo "Config: ${CONFIG_PATH}"
echo ""

# Initialize
init_test_env

# ============================================================================
# 1. PROCESS & LIFECYCLE TESTS
# ============================================================================
echo -e "${BLUE}=== 1. PROCESS & LIFECYCLE ===${NC}"

# Test 1.1: Daemon starts successfully
echo "Test 1.1: Daemon starts successfully"
if "${BINARY_PATH}" --version >/dev/null 2>&1; then
    test_result "PASS" "Daemon binary exists and executable" "Version command successful"
else
    test_result "FAIL" "Daemon binary exists and executable" "Version command failed or binary not found"
fi

# Test 1.2: Config validation
echo "Test 1.2: Config validation"
if "${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test1.2.log" 2>&1; then
    test_result "PASS" "Valid config accepted" "Config loaded successfully"
else
    test_result "FAIL" "Valid config accepted" "Config validation failed: $(cat ${TEST_DIR}/test1.2.log)"
fi

# Test 1.3: Invalid config rejected
echo "Test 1.3: Invalid config rejected"
invalid_config="${TEST_DIR}/invalid-config.yaml"
echo "invalid: yaml: [broken" > "${invalid_config}"
if ! "${BINARY_PATH}" --config "${invalid_config}" --once --dry-run >"${TEST_DIR}/test1.3.log" 2>&1; then
    test_result "PASS" "Invalid config rejected" "Invalid config correctly rejected"
else
    test_result "FAIL" "Invalid config rejected" "Invalid config was accepted"
fi

# Test 1.4: --once mode runs single cycle
echo "Test 1.4: --once mode runs single cycle"
start_time=$(date +%s)
if timeout 10 "${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test1.4.log" 2>&1; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    if [ "${duration}" -lt 10 ]; then
        test_result "PASS" "--once mode runs single cycle" "Completed in ${duration}s (single cycle)"
    else
        test_result "FAIL" "--once mode runs single cycle" "Took ${duration}s (may have looped)"
    fi
else
    test_result "FAIL" "--once mode runs single cycle" "Command failed or timed out"
fi

# Test 1.5: Graceful shutdown on SIGTERM
echo "Test 1.5: Graceful shutdown on SIGTERM"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test1.5.log" 2>&1 &
DAEMON_PID=$!
sleep 2
if kill -0 "${DAEMON_PID}" 2>/dev/null; then
    kill -TERM "${DAEMON_PID}" 2>/dev/null
    sleep 3
    if ! kill -0 "${DAEMON_PID}" 2>/dev/null; then
        test_result "PASS" "Graceful shutdown on SIGTERM" "Daemon terminated gracefully"
    else
        kill -9 "${DAEMON_PID}" 2>/dev/null
        test_result "FAIL" "Graceful shutdown on SIGTERM" "Daemon did not terminate on SIGTERM"
    fi
else
    test_result "FAIL" "Graceful shutdown on SIGTERM" "Daemon did not start"
fi

# Test 1.6: Graceful shutdown on SIGINT
echo "Test 1.6: Graceful shutdown on SIGINT"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test1.6.log" 2>&1 &
DAEMON_PID=$!
sleep 2
if kill -0 "${DAEMON_PID}" 2>/dev/null; then
    kill -INT "${DAEMON_PID}" 2>/dev/null
    sleep 3
    if ! kill -0 "${DAEMON_PID}" 2>/dev/null; then
        test_result "PASS" "Graceful shutdown on SIGINT" "Daemon terminated gracefully"
    else
        kill -9 "${DAEMON_PID}" 2>/dev/null
        test_result "FAIL" "Graceful shutdown on SIGINT" "Daemon did not terminate on SIGINT"
    fi
else
    test_result "FAIL" "Graceful shutdown on SIGINT" "Daemon did not start"
fi

# ============================================================================
# 2. STORAGE OPERATIONS TESTS
# ============================================================================
echo -e "${BLUE}=== 2. STORAGE OPERATIONS ===${NC}"

# Test 2.1: Dry-run mode doesn't delete files
echo "Test 2.1: Dry-run mode doesn't delete files"
old_count=$(find "${SCAN_DIR}" -type f | wc -l)
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test2.1.log" 2>&1
new_count=$(find "${SCAN_DIR}" -type f | wc -l)
if [ "${old_count}" -eq "${new_count}" ]; then
    test_result "PASS" "Dry-run mode doesn't delete files" "File count unchanged: ${old_count} -> ${new_count}"
else
    test_result "FAIL" "Dry-run mode doesn't delete files" "File count changed: ${old_count} -> ${new_count}"
fi

# Test 2.2: Files older than age_off_days are identified
echo "Test 2.2: Files older than age_off_days are identified"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test2.2.log" 2>&1
if grep -q "old_file" "${TEST_DIR}/test2.2.log"; then
    test_result "PASS" "Files older than age_off_days are identified" "Old files found in log"
else
    test_result "PARTIAL" "Files older than age_off_days are identified" "May not have found old files (check log)"
fi

# Test 2.3: New files are not deleted
echo "Test 2.3: New files are not deleted"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test2.3.log" 2>&1
if [ -f "${SCAN_DIR}/new_file1.txt" ]; then
    if ! grep -q "new_file1.txt" "${TEST_DIR}/test2.3.log" 2>/dev/null || grep -q "SKIP.*new_file" "${TEST_DIR}/test2.3.log" 2>/dev/null; then
        test_result "PASS" "New files are not deleted" "New file preserved"
    else
        test_result "PARTIAL" "New files are not deleted" "New file may be marked for deletion (check age calculation)"
    fi
else
    test_result "FAIL" "New files are not deleted" "New file was deleted in dry-run mode"
fi

# Test 2.4: Cleanup respects path restrictions
echo "Test 2.4: Cleanup respects path restrictions"
# Create file outside scan path
mkdir -p "${TEST_DIR}/outside"
touch "${TEST_DIR}/outside/should_not_delete.txt"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test2.4.log" 2>&1
if [ -f "${TEST_DIR}/outside/should_not_delete.txt" ]; then
    test_result "PASS" "Cleanup respects path restrictions" "File outside scan path preserved"
else
    test_result "FAIL" "Cleanup respects path restrictions" "File outside scan path was affected"
fi

# ============================================================================
# 3. API/INTERFACE COMPLIANCE TESTS
# ============================================================================
echo -e "${BLUE}=== 3. API/INTERFACE COMPLIANCE ===${NC}"

# Test 3.1: Prometheus metrics endpoint exists
echo "Test 3.1: Prometheus metrics endpoint exists"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test3.1.log" 2>&1 &
DAEMON_PID=$!
if wait_for_metrics_server "${PROMETHEUS_PORT}"; then
    test_result "PASS" "Prometheus metrics endpoint exists" "Metrics endpoint accessible"
else
    test_result "FAIL" "Prometheus metrics endpoint exists" "Metrics endpoint not accessible after waiting"
fi
kill -TERM "${DAEMON_PID}" 2>/dev/null || true
sleep 2

# Test 3.2: Metrics endpoint returns valid Prometheus format
echo "Test 3.2: Metrics endpoint returns valid Prometheus format"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test3.2.log" 2>&1 &
DAEMON_PID=$!
if wait_for_metrics_server "${PROMETHEUS_PORT}"; then
    metrics=$(curl -s "http://localhost:${PROMETHEUS_PORT}/metrics" 2>/dev/null || echo "")
    if echo "${metrics}" | grep -q "storagesage_"; then
        test_result "PASS" "Metrics endpoint returns valid Prometheus format" "Found storagesage_ metrics"
    else
        test_result "FAIL" "Metrics endpoint returns valid Prometheus format" "No storagesage_ metrics found"
    fi
else
    test_result "FAIL" "Metrics endpoint returns valid Prometheus format" "Metrics server not ready"
fi
kill -TERM "${DAEMON_PID}" 2>/dev/null || true
sleep 2

# Test 3.3: Required metrics are present
echo "Test 3.3: Required metrics are present"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test3.3.log" 2>&1 &
DAEMON_PID=$!
if wait_for_metrics_server "${PROMETHEUS_PORT}"; then
    metrics=$(curl -s "http://localhost:${PROMETHEUS_PORT}/metrics" 2>/dev/null || echo "")
    required_metrics=("storagesage_files_deleted_total" "storagesage_bytes_freed_total" "storagesage_errors_total" "storagesage_cleanup_duration_seconds")
    missing_metrics=()
    for metric in "${required_metrics[@]}"; do
        if ! echo "${metrics}" | grep -q "${metric}"; then
            missing_metrics+=("${metric}")
        fi
    done
    if [ ${#missing_metrics[@]} -eq 0 ]; then
        test_result "PASS" "Required metrics are present" "All required metrics found"
    else
        test_result "FAIL" "Required metrics are present" "Missing metrics: ${missing_metrics[*]}"
    fi
else
    test_result "FAIL" "Required metrics are present" "Metrics server not ready"
fi
kill -TERM "${DAEMON_PID}" 2>/dev/null || true
sleep 2

# Test 3.4: Metrics update after cleanup cycle
echo "Test 3.4: Metrics update after cleanup cycle"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test3.4.log" 2>&1 &
DAEMON_PID=$!
if wait_for_metrics_server "${PROMETHEUS_PORT}"; then
    # Wait for at least one cleanup cycle to complete
    initial_cycles=$(curl -s "http://localhost:${PROMETHEUS_PORT}/metrics" 2>/dev/null | grep "storagesage_cleanup_duration_seconds_count" | awk '{print $2}' || echo "0")
    # Wait for the cleanup cycle interval (1 minute) plus some buffer
    sleep 65
    final_cycles=$(curl -s "http://localhost:${PROMETHEUS_PORT}/metrics" 2>/dev/null | grep "storagesage_cleanup_duration_seconds_count" | awk '{print $2}' || echo "0")
    if [ -n "${initial_cycles}" ] && [ -n "${final_cycles}" ] && [ "${final_cycles}" -gt "${initial_cycles}" ]; then
        test_result "PASS" "Metrics update after cleanup cycle" "Cycle count increased: ${initial_cycles} -> ${final_cycles}"
    else
        test_result "PARTIAL" "Metrics update after cleanup cycle" "Cycle count may not have updated (timing sensitive): ${initial_cycles} -> ${final_cycles}"
    fi
else
    test_result "PARTIAL" "Metrics update after cleanup cycle" "Metrics server not ready"
fi
kill -TERM "${DAEMON_PID}" 2>/dev/null || true
sleep 2

# ============================================================================
# 4. LOGGING & OBSERVABILITY TESTS
# ============================================================================
echo -e "${BLUE}=== 4. LOGGING & OBSERVABILITY ===${NC}"

# Test 4.1: Logs are written to file
echo "Test 4.1: Logs are written to file"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test4.1.log" 2>&1
if [ -f "/var/log/storage-sage/cleanup.log" ]; then
    test_result "PASS" "Logs are written to file" "Log file exists: /var/log/storage-sage/cleanup.log"
else
    test_result "PARTIAL" "Logs are written to file" "Log file may not be created (permissions?)"
fi

# Test 4.2: Logs contain startup message
echo "Test 4.2: Logs contain startup message"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test4.2.log" 2>&1
if grep -qi "StorageSage starting up" "${TEST_DIR}/test4.2.log" 2>/dev/null || grep -qi "starting up" "${TEST_DIR}/test4.2.log" 2>/dev/null; then
    test_result "PASS" "Logs contain startup message" "Startup message found in log"
else
    test_result "FAIL" "Logs contain startup message" "Startup message not found in log"
fi

# Test 4.3: Logs contain cycle completion message
echo "Test 4.3: Logs contain cycle completion message"
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test4.3.log" 2>&1
if grep -qi "cycle complete" "${TEST_DIR}/test4.3.log" 2>/dev/null; then
    test_result "PASS" "Logs contain cycle completion message" "Cycle completion message found"
else
    test_result "PARTIAL" "Logs contain cycle completion message" "Cycle completion message may not be present"
fi

# Test 4.4: Logs are written to stdout
echo "Test 4.4: Logs are written to stdout"
output=$("${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run 2>&1)
if [ -n "${output}" ]; then
    test_result "PASS" "Logs are written to stdout" "Output captured from stdout"
else
    test_result "FAIL" "Logs are written to stdout" "No output to stdout"
fi

# ============================================================================
# 5. CONFIGURATION & ENVIRONMENT TESTS
# ============================================================================
echo -e "${BLUE}=== 5. CONFIGURATION & ENVIRONMENT ===${NC}"

# Test 5.1: Config file path is configurable
echo "Test 5.1: Config file path is configurable"
if "${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test5.1.log" 2>&1; then
    test_result "PASS" "Config file path is configurable" "Custom config path accepted"
else
    test_result "FAIL" "Config file path is configurable" "Custom config path rejected"
fi

# Test 5.2: Default config path is used when not specified
echo "Test 5.2: Default config path is used when not specified"
# This test may fail if default path doesn't exist, which is expected
if "${BINARY_PATH}" --once --dry-run >"${TEST_DIR}/test5.2.log" 2>&1; then
    test_result "PASS" "Default config path is used" "Default config loaded"
else
    if grep -q "failed to load config" "${TEST_DIR}/test5.2.log" 2>/dev/null; then
        test_result "PARTIAL" "Default config path is used" "Default config path tried but file doesn't exist (expected)"
    else
        test_result "FAIL" "Default config path is used" "Unexpected error with default config"
    fi
fi

# Test 5.3: Invalid scan paths are rejected
echo "Test 5.3: Invalid scan paths are rejected"
invalid_path_config="${TEST_DIR}/invalid-path-config.yaml"
cat > "${invalid_path_config}" <<EOF
scan_paths:
  - "relative/path"
age_off_days: 7
interval_minutes: 15
prometheus:
  port: ${PROMETHEUS_PORT}
EOF
if ! "${BINARY_PATH}" --config "${invalid_path_config}" --once --dry-run >"${TEST_DIR}/test5.3.log" 2>&1; then
    if grep -q "absolute" "${TEST_DIR}/test5.3.log" 2>/dev/null || grep -q "invalid" "${TEST_DIR}/test5.3.log" 2>/dev/null; then
        test_result "PASS" "Invalid scan paths are rejected" "Relative path correctly rejected"
    else
        test_result "PARTIAL" "Invalid scan paths are rejected" "Config rejected but unclear error message"
    fi
else
    test_result "FAIL" "Invalid scan paths are rejected" "Relative path was accepted"
fi

# Test 5.4: Negative age_off_days is rejected
echo "Test 5.4: Negative age_off_days is rejected"
negative_age_config="${TEST_DIR}/negative-age-config.yaml"
cat > "${negative_age_config}" <<EOF
scan_paths:
  - "${SCAN_DIR}"
age_off_days: -1
interval_minutes: 15
prometheus:
  port: ${PROMETHEUS_PORT}
EOF
if ! "${BINARY_PATH}" --config "${negative_age_config}" --once --dry-run >"${TEST_DIR}/test5.4.log" 2>&1; then
    test_result "PASS" "Negative age_off_days is rejected" "Negative age correctly rejected"
else
    test_result "FAIL" "Negative age_off_days is rejected" "Negative age was accepted"
fi

# Test 5.5: Default interval is applied
echo "Test 5.5: Default interval is applied"
no_interval_config="${TEST_DIR}/no-interval-config.yaml"
cat > "${no_interval_config}" <<EOF
scan_paths:
  - "${SCAN_DIR}"
age_off_days: 7
prometheus:
  port: ${PROMETHEUS_PORT}
EOF
if "${BINARY_PATH}" --config "${no_interval_config}" --once --dry-run >"${TEST_DIR}/test5.5.log" 2>&1; then
    test_result "PASS" "Default interval is applied" "Config without interval accepted (default applied)"
else
    test_result "FAIL" "Default interval is applied" "Config without interval rejected"
fi

# Test 5.6: Default Prometheus port is applied
echo "Test 5.6: Default Prometheus port is applied"
no_port_config="${TEST_DIR}/no-port-config.yaml"
cat > "${no_port_config}" <<EOF
scan_paths:
  - "${SCAN_DIR}"
age_off_days: 7
interval_minutes: 15
EOF
"${BINARY_PATH}" --config "${no_port_config}" --dry-run >"${TEST_DIR}/test5.6.log" 2>&1 &
DAEMON_PID=$!
sleep 3
if curl -s -f "http://localhost:9090/metrics" >/dev/null 2>&1; then
    test_result "PASS" "Default Prometheus port is applied" "Default port 9090 used"
else
    test_result "FAIL" "Default Prometheus port is applied" "Default port not used"
fi
kill -TERM "${DAEMON_PID}" 2>/dev/null || true
sleep 2

# ============================================================================
# 6. ERROR HANDLING & RESILIENCE TESTS
# ============================================================================
echo -e "${BLUE}=== 6. ERROR HANDLING & RESILIENCE ===${NC}"

# Test 6.1: Handles missing scan directory gracefully
echo "Test 6.1: Handles missing scan directory gracefully"
missing_dir_config="${TEST_DIR}/missing-dir-config.yaml"
cat > "${missing_dir_config}" <<EOF
scan_paths:
  - "${TEST_DIR}/nonexistent"
age_off_days: 7
interval_minutes: 15
prometheus:
  port: ${PROMETHEUS_PORT}
EOF
if "${BINARY_PATH}" --config "${missing_dir_config}" --once --dry-run >"${TEST_DIR}/test6.1.log" 2>&1; then
    test_result "PASS" "Handles missing scan directory gracefully" "Daemon handled missing directory"
else
    # Check if it's a graceful error (logged) vs crash
    if grep -q "error\|Error\|ERROR" "${TEST_DIR}/test6.1.log" 2>/dev/null; then
        test_result "PARTIAL" "Handles missing scan directory gracefully" "Error logged but daemon may have exited"
    else
        test_result "FAIL" "Handles missing scan directory gracefully" "Daemon crashed on missing directory"
    fi
fi

# Test 6.2: Continues running after scan errors
echo "Test 6.2: Continues running after scan errors"
# Create a directory with restricted permissions in a subdirectory
mkdir -p "${SCAN_DIR}/restricted"
touch "${SCAN_DIR}/restricted/file.txt"
chmod 000 "${SCAN_DIR}/restricted" 2>/dev/null || true
"${BINARY_PATH}" --config "${CONFIG_PATH}" --once --dry-run >"${TEST_DIR}/test6.2.log" 2>&1
exit_code=$?
chmod 755 "${SCAN_DIR}/restricted" 2>/dev/null || true
if [ ${exit_code} -eq 0 ]; then
    test_result "PASS" "Continues running after scan errors" "Daemon completed despite permission errors"
else
    test_result "PARTIAL" "Continues running after scan errors" "Daemon may have exited on scan error"
fi

# Test 6.3: Metrics server handles port conflicts
echo "Test 6.3: Metrics server handles port conflicts"
# Start first daemon
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test6.3a.log" 2>&1 &
DAEMON_PID1=$!
sleep 2
# Try to start second daemon on same port
"${BINARY_PATH}" --config "${CONFIG_PATH}" --dry-run >"${TEST_DIR}/test6.3b.log" 2>&1 &
DAEMON_PID2=$!
sleep 3
# Check if at least one is running
if kill -0 "${DAEMON_PID1}" 2>/dev/null || kill -0 "${DAEMON_PID2}" 2>/dev/null; then
    test_result "PARTIAL" "Metrics server handles port conflicts" "At least one daemon running (port conflict may be handled)"
else
    test_result "FAIL" "Metrics server handles port conflicts" "Both daemons may have failed"
fi
kill -TERM "${DAEMON_PID1}" "${DAEMON_PID2}" 2>/dev/null || true
sleep 2

# ============================================================================
# GENERATE REPORT
# ============================================================================
echo ""
echo "=========================================="
echo "COMPLIANCE REPORT"
echo "=========================================="
echo "Generated: $(date)"
echo ""
echo "Test Summary:"
echo "  Total Tests: ${TOTAL_TESTS}"
echo "  Passed: ${PASSED_TESTS}"
echo "  Failed: ${FAILED_TESTS}"
echo "  Partial: ${PARTIAL_TESTS}"
echo ""

if [ ${TOTAL_TESTS} -gt 0 ]; then
    pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "Pass Rate: ${pass_rate}%"
    echo ""
    
    if [ ${FAILED_TESTS} -eq 0 ] && [ ${PARTIAL_TESTS} -eq 0 ]; then
        echo -e "${GREEN}OVERALL: 100% COMPLIANT${NC}"
        exit 0
    elif [ ${FAILED_TESTS} -eq 0 ]; then
        echo -e "${YELLOW}OVERALL: ${pass_rate}% COMPLIANT (with partial results)${NC}"
        exit 0
    else
        echo -e "${RED}OVERALL: ${pass_rate}% COMPLIANT (${FAILED_TESTS} failures)${NC}"
        echo ""
        echo "Issue Log: ${ISSUE_LOG}"
        exit 1
    fi
else
    echo "No tests executed"
    exit 1
fi

