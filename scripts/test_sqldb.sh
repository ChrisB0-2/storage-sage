#!/bin/bash
#
# StorageSage SQL Database Test Script
#
# This script performs comprehensive testing of the SQLite database:
# 1. Unit tests (Go test suite)
# 2. Container accessibility tests (volume mounts, permissions)
# 3. Cross-container database sharing (daemon writes, backend reads)
# 4. API endpoint integration tests
# 5. Database integrity and performance checks
#
# Usage:
#   ./scripts/test_sqldb.sh [OPTIONS]
#
# Options:
#   --unit-only       Run only Go unit tests
#   --integration-only Run only integration tests
#   --verbose         Enable verbose output
#   --no-cleanup      Don't clean up test containers
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Options
RUN_UNIT=true
RUN_INTEGRATION=true
VERBOSE=false
NO_CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --unit-only)
      RUN_INTEGRATION=false
      shift
      ;;
    --integration-only)
      RUN_UNIT=false
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --no-cleanup)
      NO_CLEANUP=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--unit-only|--integration-only] [--verbose] [--no-cleanup]"
      exit 1
      ;;
  esac
done

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
  ((TESTS_PASSED++))
  ((TESTS_TOTAL++))
}

log_failure() {
  echo -e "${RED}[✗]${NC} $1"
  ((TESTS_FAILED++))
  ((TESTS_TOTAL++))
}

log_warning() {
  echo -e "${YELLOW}[!]${NC} $1"
}

log_section() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE} $1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

run_test() {
  local test_name="$1"
  local test_command="$2"

  ((TESTS_TOTAL++))

  if $VERBOSE; then
    echo -e "\n${BLUE}Running:${NC} $test_name"
    echo -e "${BLUE}Command:${NC} $test_command"
  fi

  if eval "$test_command" > /tmp/test_output_$$.log 2>&1; then
    log_success "$test_name"
    if $VERBOSE; then
      cat /tmp/test_output_$$.log
    fi
    rm -f /tmp/test_output_$$.log
    return 0
  else
    log_failure "$test_name"
    echo -e "${RED}Error output:${NC}"
    cat /tmp/test_output_$$.log
    rm -f /tmp/test_output_$$.log
    return 1
  fi
}

# =============================================================================
# UNIT TESTS
# =============================================================================

run_unit_tests() {
  log_section "Go Unit Tests"

  log_info "Running database unit tests..."

  # Run Go tests with coverage
  if $VERBOSE; then
    go test -v -race -coverprofile=coverage.out ./internal/database/
  else
    go test -race -coverprofile=coverage.out ./internal/database/
  fi

  local result=$?

  if [ $result -eq 0 ]; then
    log_success "All Go unit tests passed"

    # Display coverage
    log_info "Code coverage:"
    go tool cover -func=coverage.out | tail -5
  else
    log_failure "Go unit tests failed"
    exit 1
  fi

  echo ""
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

check_docker_services() {
  log_section "Docker Service Checks"

  # Check if docker-compose is running
  if ! docker compose ps > /dev/null 2>&1; then
    log_warning "Docker Compose services not running. Starting services..."
    docker compose up -d
    sleep 5
  fi

  # Check daemon container
  if docker compose ps storage-sage-daemon | grep -q "Up"; then
    log_success "Daemon container is running"
  else
    log_failure "Daemon container is not running"
    return 1
  fi

  # Check backend container
  if docker compose ps storage-sage-backend | grep -q "Up"; then
    log_success "Backend container is running"
  else
    log_failure "Backend container is not running"
    return 1
  fi
}

check_database_volume() {
  log_section "Database Volume Checks"

  # Check if volume exists
  if docker volume inspect storage-sage-db > /dev/null 2>&1; then
    log_success "Database volume 'storage-sage-db' exists"
  else
    log_failure "Database volume 'storage-sage-db' does not exist"
    return 1
  fi

  # Check volume mount in daemon container
  local daemon_mount=$(docker compose exec -T storage-sage-daemon mount | grep storage-sage-db || true)
  if [ -n "$daemon_mount" ]; then
    log_success "Database volume mounted in daemon container"
    $VERBOSE && echo "  Mount: $daemon_mount"
  else
    log_warning "Cannot verify volume mount in daemon (container may not be running)"
  fi

  # Check volume mount in backend container
  local backend_mount=$(docker compose exec -T storage-sage-backend mount | grep storage-sage-db || true)
  if [ -n "$backend_mount" ]; then
    log_success "Database volume mounted in backend container"
    $VERBOSE && echo "  Mount: $backend_mount"
  else
    log_warning "Cannot verify volume mount in backend (container may not be running)"
  fi
}

check_database_file() {
  log_section "Database File Checks"

  # Check if database file exists in daemon container
  if docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    log_success "Database file exists in daemon container"
  else
    log_warning "Database file does not exist yet (will be created on first write)"
  fi

  # Check WAL files
  if docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db-wal; then
    log_success "WAL file exists (indicates WAL mode is active)"
  else
    log_info "WAL file not found (normal if no writes have occurred)"
  fi

  if docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db-shm; then
    log_success "Shared memory file exists"
  else
    log_info "SHM file not found (normal if no writes have occurred)"
  fi

  # Check permissions in daemon (should be writable)
  local daemon_perm=$(docker compose exec -T storage-sage-daemon stat -c "%a" /var/lib/storage-sage 2>/dev/null || echo "N/A")
  if [ "$daemon_perm" != "N/A" ]; then
    log_info "Daemon directory permissions: $daemon_perm"
  fi

  # Check if backend can read the directory (should be read-only mount)
  if docker compose exec -T storage-sage-backend test -r /var/lib/storage-sage; then
    log_success "Backend can read database directory"
  else
    log_failure "Backend cannot read database directory"
  fi
}

check_database_schema() {
  log_section "Database Schema Checks"

  # Check if database exists
  if ! docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    log_warning "Database not initialized yet, skipping schema checks"
    return 0
  fi

  # Check tables exist
  local tables=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null || echo "")

  if echo "$tables" | grep -q "deletions"; then
    log_success "Table 'deletions' exists"
  else
    log_failure "Table 'deletions' not found"
  fi

  if echo "$tables" | grep -q "schema_version"; then
    log_success "Table 'schema_version' exists"
  else
    log_failure "Table 'schema_version' not found"
  fi

  # Check schema version
  local version=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT version FROM schema_version LIMIT 1;" 2>/dev/null || echo "N/A")
  if [ "$version" == "2" ]; then
    log_success "Schema version is 2"
  else
    log_warning "Schema version is $version (expected 2)"
  fi

  # Check indexes
  local indexes=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%';" 2>/dev/null || echo "")
  local index_count=$(echo "$indexes" | grep -c "idx_" || echo 0)

  if [ "$index_count" -eq 7 ]; then
    log_success "All 7 indexes found"
    $VERBOSE && echo "$indexes"
  else
    log_warning "Found $index_count indexes (expected 7)"
  fi

  # Check WAL mode
  local journal_mode=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA journal_mode;" 2>/dev/null || echo "N/A")
  if [ "$journal_mode" == "wal" ]; then
    log_success "WAL mode is enabled"
  else
    log_failure "WAL mode is not enabled (found: $journal_mode)"
  fi
}

test_database_write() {
  log_section "Database Write Tests"

  # Create a test file to trigger cleanup
  log_info "Creating test file to trigger database write..."

  local test_file="/test-workspace/db_test_$(date +%s).log"
  local test_content="Database write test at $(date)"

  # Create test file in daemon container
  docker compose exec -T storage-sage-daemon sh -c "echo '$test_content' > $test_file"

  if [ $? -eq 0 ]; then
    log_success "Test file created: $test_file"
  else
    log_failure "Failed to create test file"
    return 1
  fi

  # Wait for daemon to potentially process it (if running)
  sleep 2

  # Check if database has records
  if docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    local record_count=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions;" 2>/dev/null || echo "0")
    log_info "Database contains $record_count records"

    if [ "$record_count" -gt 0 ]; then
      log_success "Database has deletion records"
    else
      log_info "No deletion records yet (depends on cleanup configuration)"
    fi
  else
    log_info "Database not created yet (no deletions triggered)"
  fi
}

test_database_read_from_backend() {
  log_section "Cross-Container Database Read Tests"

  # Check if database exists
  if ! docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    log_warning "Database not initialized, skipping backend read tests"
    return 0
  fi

  # Verify backend can read the database file
  if docker compose exec -T storage-sage-backend test -r /var/lib/storage-sage/deletions.db; then
    log_success "Backend can read database file"
  else
    log_failure "Backend cannot read database file"
    return 1
  fi

  # Test backend cannot write (read-only mount)
  if docker compose exec -T storage-sage-backend sh -c "echo 'test' > /var/lib/storage-sage/test.txt 2>/dev/null"; then
    log_failure "Backend can write to database directory (should be read-only!)"
    docker compose exec -T storage-sage-backend rm -f /var/lib/storage-sage/test.txt 2>/dev/null || true
  else
    log_success "Backend database directory is read-only (as expected)"
  fi
}

test_api_endpoints() {
  log_section "API Endpoint Tests"

  # Check if backend is responding
  local health_check=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/api/v1/health 2>/dev/null || echo "000")

  if [ "$health_check" == "200" ]; then
    log_success "Backend health check passed"
  else
    log_failure "Backend health check failed (HTTP $health_check)"
    return 1
  fi

  # Note: Database API endpoints may require authentication
  log_info "Testing database-related API endpoints would require authentication"
  log_info "Skipping authenticated endpoint tests (add JWT token for full testing)"
}

test_database_performance() {
  log_section "Database Performance Tests"

  # Check if database exists
  if ! docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    log_warning "Database not initialized, skipping performance tests"
    return 0
  fi

  # Check database size
  local db_size=$(docker compose exec -T storage-sage-daemon stat -c "%s" /var/lib/storage-sage/deletions.db 2>/dev/null || echo "0")
  local db_size_mb=$((db_size / 1024 / 1024))
  log_info "Database size: ${db_size_mb} MB"

  # Check page count and page size
  local page_count=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA page_count;" 2>/dev/null || echo "0")
  local page_size=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA page_size;" 2>/dev/null || echo "0")
  log_info "Pages: $page_count × $page_size bytes"

  # Run integrity check
  log_info "Running database integrity check..."
  local integrity=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA integrity_check;" 2>/dev/null || echo "error")

  if [ "$integrity" == "ok" ]; then
    log_success "Database integrity check passed"
  else
    log_failure "Database integrity check failed: $integrity"
  fi
}

test_concurrent_access() {
  log_section "Concurrent Access Tests"

  # Check if database exists
  if ! docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    log_warning "Database not initialized, skipping concurrent access tests"
    return 0
  fi

  log_info "Testing concurrent read access from both containers..."

  # Perform simultaneous reads from daemon and backend
  docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions;" > /tmp/daemon_read.txt 2>&1 &
  local daemon_pid=$!

  docker compose exec -T storage-sage-backend sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions;" > /tmp/backend_read.txt 2>&1 &
  local backend_pid=$!

  # Wait for both to complete
  wait $daemon_pid
  local daemon_result=$?
  wait $backend_pid
  local backend_result=$?

  if [ $daemon_result -eq 0 ] && [ $backend_result -eq 0 ]; then
    log_success "Concurrent reads from both containers succeeded"
    $VERBOSE && echo "  Daemon result: $(cat /tmp/daemon_read.txt)"
    $VERBOSE && echo "  Backend result: $(cat /tmp/backend_read.txt)"
  else
    log_failure "Concurrent read test failed"
  fi

  rm -f /tmp/daemon_read.txt /tmp/backend_read.txt
}

test_database_backup() {
  log_section "Database Backup/Restore Tests"

  # Check if database exists
  if ! docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    log_warning "Database not initialized, skipping backup tests"
    return 0
  fi

  # Create backup
  log_info "Creating database backup..."
  docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db ".backup /var/lib/storage-sage/deletions_backup.db"

  if [ $? -eq 0 ]; then
    log_success "Database backup created"
  else
    log_failure "Database backup failed"
    return 1
  fi

  # Verify backup
  if docker compose exec -T storage-sage-daemon test -f /var/lib/storage-sage/deletions_backup.db; then
    log_success "Backup file exists"

    # Compare record counts
    local original_count=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions;" 2>/dev/null || echo "0")
    local backup_count=$(docker compose exec -T storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions_backup.db "SELECT COUNT(*) FROM deletions;" 2>/dev/null || echo "0")

    if [ "$original_count" == "$backup_count" ]; then
      log_success "Backup contains same number of records ($backup_count)"
    else
      log_failure "Backup record count mismatch (original: $original_count, backup: $backup_count)"
    fi

    # Cleanup backup
    docker compose exec -T storage-sage-daemon rm -f /var/lib/storage-sage/deletions_backup.db
  else
    log_failure "Backup file not found"
  fi
}

run_integration_tests() {
  check_docker_services || return 1
  check_database_volume || return 1
  check_database_file || return 1
  check_database_schema || return 1
  test_database_write || return 1
  test_database_read_from_backend || return 1
  test_api_endpoints || return 1
  test_database_performance || return 1
  test_concurrent_access || return 1
  test_database_backup || return 1
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  log_section "StorageSage SQL Database Test Suite"
  echo "Starting database tests..."
  echo "  Unit tests: $RUN_UNIT"
  echo "  Integration tests: $RUN_INTEGRATION"
  echo "  Verbose: $VERBOSE"
  echo ""

  # Run unit tests
  if $RUN_UNIT; then
    run_unit_tests
  fi

  # Run integration tests
  if $RUN_INTEGRATION; then
    run_integration_tests
  fi

  # Summary
  log_section "Test Summary"
  echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
  echo -e "Total tests:  $TESTS_TOTAL"
  echo ""

  if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
  fi
}

# Run main
main
