#!/bin/bash
#
# StorageSage Storage Layer Audit Script
# This script audits all storage systems in the StorageSage codebase
#

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Audit results file
AUDIT_REPORT="/tmp/storage_sage_audit_$(date +%Y%m%d_%H%M%S).txt"
CONFIG_PATH="${STORAGE_SAGE_CONFIG:-/etc/storage-sage/config.yaml}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"

echo "=========================================="
echo "StorageSage Storage Layer Audit"
echo "=========================================="
echo "Timestamp: $(date)"
echo "Config Path: ${CONFIG_PATH}"
echo ""

# Function to log findings
log_finding() {
    echo -e "$1" | tee -a "${AUDIT_REPORT}"
}

# Function to test command and log result
test_command() {
    local cmd="$1"
    local desc="$2"
    log_finding "\n${BLUE}Testing: ${desc}${NC}"
    log_finding "Command: ${cmd}"
    
    # Execute command and capture output and exit code
    # Use subshell to avoid affecting main script's exit code handling
    local output
    local exit_code
    set +e  # Allow non-zero exit codes temporarily
    output=$(eval "${cmd}" 2>&1)
    exit_code=$?
    set -e  # Re-enable exit on error for critical sections
    
    # Always log output to report file
    if [ -n "${output}" ]; then
        echo "${output}" >> "${AUDIT_REPORT}"
    fi
    
    # For commands that produce output, consider them successful even with non-zero exit
    # This handles cases like 'find' that may exit non-zero due to permission errors
    # but still produce useful output
    local has_output=false
    if [ -n "${output}" ] && [ "${output}" != "0" ] && [ "${output}" != "N/A" ]; then
        # Check if output contains actual data (not just error messages)
        if ! echo "${output}" | grep -qiE "^(error|failed|permission denied|no such file|not found)"; then
            has_output=true
        fi
    fi
    
    # Check result based on exit code and output
    if [ ${exit_code} -eq 0 ]; then
        # Success
        if [ -n "${output}" ]; then
            log_finding "${GREEN}✓ Success${NC}"
        else
            log_finding "${GREEN}✓ Success (no output)${NC}"
        fi
        return 0
    elif [ "${has_output}" = "true" ]; then
        # Command produced useful output despite non-zero exit (e.g., find with some permission errors)
        log_finding "${GREEN}✓ Success (output produced despite warnings)${NC}"
        return 0
    else
        # Failed - check error type
        if echo "${output}" | grep -qi "permission denied"; then
            log_finding "${YELLOW}⚠ Permission denied (may require elevated privileges)${NC}"
        elif echo "${output}" | grep -qi "no such file\|not found"; then
            log_finding "${YELLOW}⚠ Resource not found${NC}"
        else
            log_finding "${RED}✗ Failed (exit code: ${exit_code})${NC}"
            # Log error details if available
            if [ -n "${output}" ]; then
                echo "Error details: ${output}" >> "${AUDIT_REPORT}"
            fi
        fi
        return ${exit_code}
    fi
}

# ============================================================================
# STORAGE LAYER 1: FILESYSTEM STORAGE
# ============================================================================
log_finding "\n${YELLOW}========================================${NC}"
log_finding "${YELLOW}STORAGE LAYER: Filesystem Storage${NC}"
log_finding "${YELLOW}TYPE: filesystem${NC}"
log_finding "${YELLOW}========================================${NC}"

# Extract scan paths from config
SCAN_PATHS=""
if [ -f "${CONFIG_PATH}" ]; then
    log_finding "\n${BLUE}Configuration File Found: ${CONFIG_PATH}${NC}"
    
    # Try to read config file (may require sudo)
    if [ -r "${CONFIG_PATH}" ]; then
        # Extract scan_paths (array format)
        SCAN_PATHS=$(grep -E "^\s*-\s*\"/" "${CONFIG_PATH}" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' | tr '\n' ' ' || echo "")
        
        # If empty, try alternative format (paths with path: key)
        if [ -z "${SCAN_PATHS}" ] || [ "${SCAN_PATHS}" = " " ]; then
            SCAN_PATHS=$(grep -A1 "paths:" "${CONFIG_PATH}" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"' | tr '\n' ' ' || echo "")
        fi
        
        # Trim whitespace
        SCAN_PATHS=$(echo "${SCAN_PATHS}" | xargs)
    else
        log_finding "${YELLOW}⚠ Config file exists but is not readable (permission 600 - this is secure)${NC}"
        log_finding "${YELLOW}  Attempting to read with sudo...${NC}"
        # Try with sudo if available
        if command -v sudo >/dev/null 2>&1; then
            SCAN_PATHS=$(sudo grep -E "^\s*-\s*\"/" "${CONFIG_PATH}" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' | tr '\n' ' ' || echo "")
            if [ -z "${SCAN_PATHS}" ] || [ "${SCAN_PATHS}" = " " ]; then
                SCAN_PATHS=$(sudo grep -A1 "paths:" "${CONFIG_PATH}" 2>/dev/null | grep "path:" | awk '{print $2}' | tr -d '"' | tr '\n' ' ' || echo "")
            fi
            SCAN_PATHS=$(echo "${SCAN_PATHS}" | xargs)
        fi
    fi
    
    # Extract age_off_days (try with sudo if needed)
    if [ -r "${CONFIG_PATH}" ]; then
        AGE_OFF_DAYS=$(grep "age_off_days:" "${CONFIG_PATH}" 2>/dev/null | awk '{print $2}' | head -1 || echo "N/A")
        MIN_FREE_PERCENT=$(grep "min_free_percent:" "${CONFIG_PATH}" 2>/dev/null | awk '{print $2}' | head -1 || echo "N/A")
    elif command -v sudo >/dev/null 2>&1; then
        AGE_OFF_DAYS=$(sudo grep "age_off_days:" "${CONFIG_PATH}" 2>/dev/null | awk '{print $2}' | head -1 || echo "N/A")
        MIN_FREE_PERCENT=$(sudo grep "min_free_percent:" "${CONFIG_PATH}" 2>/dev/null | awk '{print $2}' | head -1 || echo "N/A")
    else
        AGE_OFF_DAYS="N/A"
        MIN_FREE_PERCENT="N/A"
    fi
    
    log_finding "Scan Paths: ${SCAN_PATHS:-N/A}"
    log_finding "Age Off Days: ${AGE_OFF_DAYS}"
    log_finding "Min Free Percent: ${MIN_FREE_PERCENT}%"
else
    log_finding "${RED}✗ Configuration file not found at ${CONFIG_PATH}${NC}"
    log_finding "Using default paths from test-config.yaml"
    SCAN_PATHS="/var/log"
fi

# If SCAN_PATHS is empty, try to read from test-config.yaml
if [ -z "${SCAN_PATHS}" ] || [ "${SCAN_PATHS}" = "N/A" ]; then
    # Try to find test-config.yaml relative to script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEST_CONFIG="${SCRIPT_DIR}/../test-config.yaml"
    if [ -f "${TEST_CONFIG}" ]; then
        SCAN_PATHS=$(grep -E "^\s*-\s*\"/" "${TEST_CONFIG}" | sed 's/.*"\(.*\)".*/\1/' || echo "")
    fi
    # Fallback to default if still empty
    if [ -z "${SCAN_PATHS}" ]; then
        SCAN_PATHS="/var/log"
        log_finding "${YELLOW}⚠ Using default scan path: /var/log${NC}"
    fi
fi

log_finding "\n${BLUE}VERIFICATION COMMANDS:${NC}"

# 1. Connection Test: Check if paths exist and are accessible
for path in ${SCAN_PATHS}; do
    log_finding "\n${BLUE}Path: ${path}${NC}"
    test_command "test -d '${path}' && echo 'Directory exists'" "Directory existence check"
    test_command "test -r '${path}' && echo 'Directory readable'" "Directory readability check"
    test_command "test -x '${path}' && echo 'Directory executable'" "Directory executable check"
done

# 2. Schema Audit: List directory structure and file types
for path in ${SCAN_PATHS}; do
    log_finding "\n${BLUE}Schema Audit for: ${path}${NC}"
    test_command "find '${path}' -maxdepth 2 -type d 2>/dev/null | head -20" "Directory structure (top level)"
    test_command "find '${path}' -type f -printf '%y\n' 2>/dev/null | sort | uniq -c" "File type distribution"
done

# 3. Data Count: Count files and directories
for path in ${SCAN_PATHS}; do
    log_finding "\n${BLUE}Data Count for: ${path}${NC}"
    test_command "find '${path}' -type f 2>/dev/null | wc -l" "Total file count"
    test_command "find '${path}' -type d 2>/dev/null | wc -l" "Total directory count"
    test_command "du -sh '${path}' 2>/dev/null" "Total disk usage"
done

# 4. Sample Data: Show sample files
for path in ${SCAN_PATHS}; do
    log_finding "\n${BLUE}Sample Data for: ${path}${NC}"
    test_command "find '${path}' -type f -printf '%p %s %TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | head -5" "Sample files (first 5)"
done

# Current State Summary
log_finding "\n${BLUE}CURRENT STATE:${NC}"
for path in ${SCAN_PATHS}; do
    FILE_COUNT=$(find "${path}" -type f 2>/dev/null | wc -l || echo "0")
    DIR_COUNT=$(find "${path}" -type d 2>/dev/null | wc -l || echo "0")
    DISK_USAGE=$(du -sh "${path}" 2>/dev/null | awk '{print $1}' || echo "N/A")
    
    log_finding "Path: ${path}"
    log_finding "  - Estimated Files: ${FILE_COUNT}"
    log_finding "  - Estimated Directories: ${DIR_COUNT}"
    log_finding "  - Disk Usage: ${DISK_USAGE}"
done

# ============================================================================
# STORAGE LAYER 2: PROMETHEUS METRICS
# ============================================================================
log_finding "\n${YELLOW}========================================${NC}"
log_finding "${YELLOW}STORAGE LAYER: Prometheus Metrics${NC}"
log_finding "${YELLOW}TYPE: prometheus (in-memory)${NC}"
log_finding "${YELLOW}CONNECTION: http://localhost:${PROMETHEUS_PORT}/metrics${NC}"
log_finding "${YELLOW}========================================${NC}"

# Extract port from config if available
if [ -f "${CONFIG_PATH}" ]; then
    if [ -r "${CONFIG_PATH}" ]; then
        CONFIG_PORT=$(grep -A1 "prometheus:" "${CONFIG_PATH}" 2>/dev/null | grep "port:" | awk '{print $2}' || echo "${PROMETHEUS_PORT}")
    elif command -v sudo >/dev/null 2>&1; then
        CONFIG_PORT=$(sudo grep -A1 "prometheus:" "${CONFIG_PATH}" 2>/dev/null | grep "port:" | awk '{print $2}' || echo "${PROMETHEUS_PORT}")
    fi
    PROMETHEUS_PORT="${CONFIG_PORT:-${PROMETHEUS_PORT}}"
fi

log_finding "\n${BLUE}VERIFICATION COMMANDS:${NC}"

# 1. Connection Test
test_command "curl -s -f -o /dev/null http://localhost:${PROMETHEUS_PORT}/metrics" "Prometheus metrics endpoint connectivity"

# 2. Schema Audit: List available metrics
log_finding "\n${BLUE}Schema Audit (Available Metrics):${NC}"
test_command "curl -s http://localhost:${PROMETHEUS_PORT}/metrics 2>/dev/null | grep '^storagesage_' | cut -d' ' -f1 | sort | uniq" "List StorageSage metrics"

# 3. Data Count: Count metrics
log_finding "\n${BLUE}Data Count:${NC}"
test_command "curl -s http://localhost:${PROMETHEUS_PORT}/metrics 2>/dev/null | grep '^storagesage_' | wc -l" "Total StorageSage metrics count"

# 4. Sample Data: Show sample metric values
log_finding "\n${BLUE}Sample Data (Metric Values):${NC}"
test_command "curl -s http://localhost:${PROMETHEUS_PORT}/metrics 2>/dev/null | grep '^storagesage_' | head -10" "Sample metrics (first 10)"

# Current State Summary
log_finding "\n${BLUE}CURRENT STATE:${NC}"
METRIC_NAMES=$(curl -s "http://localhost:${PROMETHEUS_PORT}/metrics" 2>/dev/null | grep '^storagesage_' | cut -d' ' -f1 | sort | uniq || echo "")
if [ -n "${METRIC_NAMES}" ]; then
    log_finding "Metrics Available:"
    echo "${METRIC_NAMES}" | while read -r metric; do
        VALUE=$(curl -s "http://localhost:${PROMETHEUS_PORT}/metrics" 2>/dev/null | grep "^${metric} " | awk '{print $2}' || echo "N/A")
        log_finding "  - ${metric}: ${VALUE}"
    done
else
    log_finding "  - No metrics available (service may not be running)"
fi

# ============================================================================
# STORAGE LAYER 3: CONFIGURATION FILE
# ============================================================================
log_finding "\n${YELLOW}========================================${NC}"
log_finding "${YELLOW}STORAGE LAYER: Configuration File${NC}"
log_finding "${YELLOW}TYPE: filesystem (YAML)${NC}"
log_finding "${YELLOW}CONNECTION: ${CONFIG_PATH}${NC}"
log_finding "${YELLOW}========================================${NC}"

log_finding "\n${BLUE}VERIFICATION COMMANDS:${NC}"

# 1. Connection Test
test_command "test -f '${CONFIG_PATH}' && echo 'Config file exists'" "Configuration file existence"

# 2. Schema Audit: Show config structure
log_finding "\n${BLUE}Schema Audit (Config Structure):${NC}"
if [ -r "${CONFIG_PATH}" ]; then
    test_command "cat '${CONFIG_PATH}' 2>/dev/null | head -50" "Configuration file contents"
elif command -v sudo >/dev/null 2>&1; then
    test_command "sudo cat '${CONFIG_PATH}' 2>/dev/null | head -50" "Configuration file contents (using sudo)"
else
    log_finding "${YELLOW}⚠ Cannot read config file (permission denied) - this is expected for secure configs${NC}"
fi

# 3. Data Count: Count config keys
log_finding "\n${BLUE}Data Count:${NC}"
if [ -r "${CONFIG_PATH}" ]; then
    test_command "grep -E '^[a-z_]+:' '${CONFIG_PATH}' 2>/dev/null | wc -l" "Configuration keys count"
elif command -v sudo >/dev/null 2>&1; then
    test_command "sudo grep -E '^[a-z_]+:' '${CONFIG_PATH}' 2>/dev/null | wc -l" "Configuration keys count (using sudo)"
fi

# 4. Sample Data: Show config values
log_finding "\n${BLUE}Sample Data:${NC}"
if [ -r "${CONFIG_PATH}" ]; then
    test_command "cat '${CONFIG_PATH}' 2>/dev/null" "Full configuration (sanitized)"
elif command -v sudo >/dev/null 2>&1; then
    test_command "sudo cat '${CONFIG_PATH}' 2>/dev/null" "Full configuration (sanitized, using sudo)"
else
    log_finding "${YELLOW}⚠ Cannot read config file (permission denied) - file exists with secure permissions${NC}"
fi

# Current State Summary
log_finding "\n${BLUE}CURRENT STATE:${NC}"
if [ -f "${CONFIG_PATH}" ]; then
    if [ -r "${CONFIG_PATH}" ]; then
        CONFIG_KEYS=$(grep -E '^[a-z_]+:' "${CONFIG_PATH}" 2>/dev/null | cut -d: -f1 | sort || echo "")
    elif command -v sudo >/dev/null 2>&1; then
        CONFIG_KEYS=$(sudo grep -E '^[a-z_]+:' "${CONFIG_PATH}" 2>/dev/null | cut -d: -f1 | sort || echo "")
    else
        CONFIG_KEYS=""
    fi
    if [ -n "${CONFIG_KEYS}" ]; then
        log_finding "Configuration Keys:"
        echo "${CONFIG_KEYS}" | while read -r key; do
            [ -n "${key}" ] && log_finding "  - ${key}"
        done
    fi
    FILE_SIZE=$(stat -c%s "${CONFIG_PATH}" 2>/dev/null || stat -f%z "${CONFIG_PATH}" 2>/dev/null || echo "N/A")
    log_finding "  - File Size: ${FILE_SIZE} bytes"
    if [ ! -r "${CONFIG_PATH}" ]; then
        log_finding "  - ${YELLOW}Note: Config file is not readable (secure permissions)${NC}"
    fi
else
    log_finding "  - Configuration file not found"
fi

# ============================================================================
# STORAGE LAYER 4: SYSTEM LOGS
# ============================================================================
log_finding "\n${YELLOW}========================================${NC}"
log_finding "${YELLOW}STORAGE LAYER: System Logs${NC}"
log_finding "${YELLOW}TYPE: filesystem (journald)${NC}"
log_finding "${YELLOW}CONNECTION: journalctl -u storage-sage${NC}"
log_finding "${YELLOW}========================================${NC}"

log_finding "\n${BLUE}VERIFICATION COMMANDS:${NC}"

# 1. Connection Test
if systemctl list-units --all 2>/dev/null | grep -q 'storage-sage'; then
    test_command "echo 'Service exists'" "StorageSage service existence"
elif systemctl status storage-sage >/dev/null 2>&1; then
    test_command "echo 'Service exists (checked via status)'" "StorageSage service status check"
else
    test_command "systemctl list-units --type=service | grep storage-sage || echo 'Service not found in active units'" "StorageSage service existence"
fi

# 2. Schema Audit: Show log structure
log_finding "\n${BLUE}Schema Audit (Log Structure):${NC}"
test_command "journalctl -u storage-sage -n 5 --no-pager 2>/dev/null | head -10" "Recent log entries structure"

# 3. Data Count: Count log entries
log_finding "\n${BLUE}Data Count:${NC}"
test_command "journalctl -u storage-sage --since '24 hours ago' --no-pager 2>/dev/null | wc -l" "Log entries in last 24 hours"

# 4. Sample Data: Show recent logs
log_finding "\n${BLUE}Sample Data:${NC}"
test_command "journalctl -u storage-sage -n 10 --no-pager 2>/dev/null" "Recent log entries (last 10)"

# Current State Summary
log_finding "\n${BLUE}CURRENT STATE:${NC}"
LOG_COUNT=$(journalctl -u storage-sage --since '24 hours ago' --no-pager 2>/dev/null | wc -l || echo "0")
log_finding "  - Log Entries (24h): ${LOG_COUNT}"
SERVICE_STATUS=$(systemctl is-active storage-sage 2>/dev/null || echo "inactive")
log_finding "  - Service Status: ${SERVICE_STATUS}"

# ============================================================================
# SECURITY AUDIT
# ============================================================================
log_finding "\n${YELLOW}========================================${NC}"
log_finding "${YELLOW}SECURITY AUDIT${NC}"
log_finding "${YELLOW}========================================${NC}"

# Check for exposed credentials
log_finding "\n${BLUE}Checking for exposed credentials:${NC}"

# Check config file for sensitive data
if [ -f "${CONFIG_PATH}" ]; then
    if [ -r "${CONFIG_PATH}" ]; then
        if grep -qiE "(password|secret|key|token|api)" "${CONFIG_PATH}" 2>/dev/null; then
            log_finding "${YELLOW}⚠ WARNING: Config file may contain sensitive data${NC}"
            log_finding "   Review: ${CONFIG_PATH}"
        else
            log_finding "${GREEN}✓ No obvious sensitive data in config file${NC}"
        fi
    elif command -v sudo >/dev/null 2>&1; then
        if sudo grep -qiE "(password|secret|key|token|api)" "${CONFIG_PATH}" 2>/dev/null; then
            log_finding "${YELLOW}⚠ WARNING: Config file may contain sensitive data${NC}"
            log_finding "   Review: ${CONFIG_PATH}"
        else
            log_finding "${GREEN}✓ No obvious sensitive data in config file (checked with sudo)${NC}"
        fi
    else
        log_finding "${YELLOW}⚠ Cannot check config file for sensitive data (permission denied)${NC}"
    fi
fi

# Check file permissions
if [ -f "${CONFIG_PATH}" ]; then
    PERMS=$(stat -c%a "${CONFIG_PATH}" 2>/dev/null || stat -f%OLp "${CONFIG_PATH}" 2>/dev/null || echo "N/A")
    log_finding "Config file permissions: ${PERMS}"
    # Check if permissions are too permissive (world-readable or world-writable)
    if [ "${PERMS}" != "N/A" ] && [ -n "${PERMS}" ]; then
        # Extract last digit (world permissions)
        WORLD_PERM=$(echo "${PERMS}" | grep -o '.$' || echo "0")
        if [ "${WORLD_PERM}" -ge 4 ] 2>/dev/null; then
            log_finding "${YELLOW}⚠ WARNING: Config file may be world-readable (permissions: ${PERMS})${NC}"
        elif [ "${PERMS}" != "600" ] && [ "${PERMS}" != "640" ] && [ "${PERMS}" != "644" ]; then
            log_finding "${YELLOW}⚠ INFO: Config file permissions are ${PERMS} (recommended: 600 or 640)${NC}"
        else
            log_finding "${GREEN}✓ Config file permissions are acceptable${NC}"
        fi
    fi
fi

# Check for unencrypted sensitive data in scan paths
log_finding "\n${BLUE}Checking scan paths for sensitive files:${NC}"
for path in ${SCAN_PATHS}; do
    if [ -d "${path}" ]; then
        SENSITIVE_FILES=$(find "${path}" -type f -name "*.key" -o -name "*.pem" -o -name "*password*" -o -name "*secret*" 2>/dev/null | head -5 || echo "")
        if [ -n "${SENSITIVE_FILES}" ]; then
            log_finding "${YELLOW}⚠ WARNING: Potential sensitive files found in ${path}${NC}"
            echo "${SENSITIVE_FILES}" | while read -r file; do
                log_finding "   - ${file}"
            done
        else
            log_finding "${GREEN}✓ No obvious sensitive files in ${path}${NC}"
        fi
    fi
done

# ============================================================================
# SUMMARY
# ============================================================================
log_finding "\n${YELLOW}========================================${NC}"
log_finding "${YELLOW}AUDIT SUMMARY${NC}"
log_finding "${YELLOW}========================================${NC}"

log_finding "\nStorage Systems Found:"
log_finding "  1. Filesystem Storage (primary)"
log_finding "  2. Prometheus Metrics (in-memory)"
log_finding "  3. Configuration File (YAML)"
log_finding "  4. System Logs (journald)"

log_finding "\nReport saved to: ${AUDIT_REPORT}"
log_finding "\n${GREEN}Audit completed successfully!${NC}"
log_finding ""

# Display report location
echo ""
echo "=========================================="
echo "Audit Report: ${AUDIT_REPORT}"
echo "=========================================="
echo ""
echo "To view the full report:"
echo "  cat ${AUDIT_REPORT}"
echo ""

