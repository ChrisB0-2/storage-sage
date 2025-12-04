#!/bin/bash
# StorageSage Single-Command Startup
# Starts: daemon + backend + frontend + metrics in one command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
DAEMON_CONFIG="${DAEMON_CONFIG:-${PROJECT_ROOT}/web/config/config.yaml}"
DAEMON_BINARY="${PROJECT_ROOT}/build/storage-sage"
BACKEND_BINARY="${PROJECT_ROOT}/build/storage-sage-web"
FRONTEND_DIST="${PROJECT_ROOT}/web/frontend-v2/dist"
LOG_DIR="${PROJECT_ROOT}/logs"
PID_DIR="${PROJECT_ROOT}/.pids"

BACKEND_PORT="${BACKEND_PORT:-8443}"
DAEMON_METRICS_PORT="${DAEMON_METRICS_PORT:-9090}"

# PID files
DAEMON_PID_FILE="${PID_DIR}/daemon.pid"
BACKEND_PID_FILE="${PID_DIR}/backend.pid"

# Options
AUTO_BUILD="${AUTO_BUILD:-true}"
FOREGROUND="${FOREGROUND:-false}"
SKIP_HEALTH_CHECK="${SKIP_HEALTH_CHECK:-false}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

show_banner() {
    echo -e "${CYAN}"
    echo "========================================"
    echo "  StorageSage Unified Startup"
    echo "========================================"
    echo -e "${NC}"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -h, --help              Show this help message
  --no-build              Skip auto-build step
  --foreground            Run in foreground (logs to console)
  --skip-health-check     Skip health checks after startup

ENVIRONMENT VARIABLES:
  DAEMON_CONFIG           Path to daemon config (default: web/config/config.yaml)
  BACKEND_PORT            Backend HTTPS port (default: 8443)
  DAEMON_METRICS_PORT     Daemon metrics port (default: 9090)
  AUTO_BUILD              Auto-build before start (default: true)

EXAMPLES:
  # Start everything (auto-builds if needed)
  $0

  # Start without rebuilding
  $0 --no-build

  # Run in foreground for debugging
  $0 --foreground

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --no-build)
                AUTO_BUILD="false"
                shift
                ;;
            --foreground)
                FOREGROUND="true"
                shift
                ;;
            --skip-health-check)
                SKIP_HEALTH_CHECK="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

validate_environment() {
    log_info "Validating environment..."

    local errors=0

    # Check for Go
    if ! command -v go &> /dev/null; then
        log_error "Go not found. Install Go 1.21+"
        errors=$((errors + 1))
    else
        log_success "Go: $(go version)"
    fi

    # Check for npm
    if ! command -v npm &> /dev/null; then
        log_error "npm not found. Install Node.js/npm"
        errors=$((errors + 1))
    else
        log_success "npm: $(npm --version)"
    fi

    # Check for curl (for health checks)
    if ! command -v curl &> /dev/null; then
        log_warn "curl not found, health checks will be skipped"
    fi

    # Check port availability
    if command -v lsof &> /dev/null; then
        if lsof -i ":${BACKEND_PORT}" &> /dev/null; then
            log_error "Port ${BACKEND_PORT} already in use"
            lsof -i ":${BACKEND_PORT}"
            errors=$((errors + 1))
        fi

        if lsof -i ":${DAEMON_METRICS_PORT}" &> /dev/null; then
            log_error "Port ${DAEMON_METRICS_PORT} already in use"
            lsof -i ":${DAEMON_METRICS_PORT}"
            errors=$((errors + 1))
        fi
    fi

    if [ $errors -gt 0 ]; then
        log_error "Environment validation failed with $errors error(s)"
        return 1
    fi

    log_success "Environment validated"
    return 0
}

check_build_artifacts() {
    log_info "Checking build artifacts..."

    if [ -f "$DAEMON_BINARY" ] && [ -f "$BACKEND_BINARY" ] && [ -d "$FRONTEND_DIST" ]; then
        log_success "All build artifacts present"
        return 0
    else
        log_warn "Build artifacts missing or incomplete"
        return 1
    fi
}

build_all() {
    log_info "Building all components..."

    if [ ! -x "${SCRIPT_DIR}/build-all.sh" ]; then
        log_error "build-all.sh not found or not executable"
        return 1
    fi

    if ! "${SCRIPT_DIR}/build-all.sh"; then
        log_error "Build failed"
        return 1
    fi

    log_success "Build completed"
    return 0
}

setup_directories() {
    log_info "Setting up directories..."

    mkdir -p "$LOG_DIR"
    mkdir -p "$PID_DIR"

    log_success "Directories created"
}

stop_existing_processes() {
    log_info "Checking for existing processes..."

    # Check and stop daemon
    if [ -f "$DAEMON_PID_FILE" ]; then
        local pid
        pid=$(cat "$DAEMON_PID_FILE")
        if ps -p "$pid" &> /dev/null; then
            log_warn "Stopping existing daemon (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 2
        fi
        rm -f "$DAEMON_PID_FILE"
    fi

    # Check and stop backend
    if [ -f "$BACKEND_PID_FILE" ]; then
        local pid
        pid=$(cat "$BACKEND_PID_FILE")
        if ps -p "$pid" &> /dev/null; then
            log_warn "Stopping existing backend (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 2
        fi
        rm -f "$BACKEND_PID_FILE"
    fi
}

start_daemon() {
    log_info "Starting StorageSage daemon..."

    if [ ! -f "$DAEMON_CONFIG" ]; then
        log_error "Daemon config not found: $DAEMON_CONFIG"
        return 1
    fi

    if [ ! -x "$DAEMON_BINARY" ]; then
        log_error "Daemon binary not found or not executable: $DAEMON_BINARY"
        return 1
    fi

    # Start daemon in background
    nohup "$DAEMON_BINARY" --config "$DAEMON_CONFIG" \
        > "${LOG_DIR}/daemon.log" 2>&1 &

    local daemon_pid=$!
    echo "$daemon_pid" > "$DAEMON_PID_FILE"

    # Wait for daemon to start
    sleep 2

    if ! ps -p "$daemon_pid" &> /dev/null; then
        log_error "Daemon failed to start"
        if [ -f "${LOG_DIR}/daemon.log" ]; then
            echo "Last 10 lines of daemon log:"
            tail -10 "${LOG_DIR}/daemon.log" | sed 's/^/  /'
        fi
        return 1
    fi

    log_success "Daemon started (PID: $daemon_pid)"
    return 0
}

start_backend() {
    log_info "Starting StorageSage backend..."

    if [ ! -x "$BACKEND_BINARY" ]; then
        log_error "Backend binary not found or not executable: $BACKEND_BINARY"
        return 1
    fi

    if [ ! -d "$FRONTEND_DIST" ]; then
        log_error "Frontend dist not found: $FRONTEND_DIST"
        return 1
    fi

    # Check for TLS certificates
    if [ ! -f "${PROJECT_ROOT}/web/certs/server.crt" ] || [ ! -f "${PROJECT_ROOT}/web/certs/server.key" ]; then
        log_warn "TLS certificates not found, generating self-signed..."
        mkdir -p "${PROJECT_ROOT}/web/certs"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${PROJECT_ROOT}/web/certs/server.key" \
            -out "${PROJECT_ROOT}/web/certs/server.crt" \
            -subj "/CN=localhost" 2>/dev/null || {
                log_error "Failed to generate TLS certificates"
                return 1
            }
        chmod 600 "${PROJECT_ROOT}/web/certs/server.key"
        log_success "TLS certificates generated"
    fi

    # Set JWT secret if not already set
    if [ -z "${JWT_SECRET:-}" ]; then
        export JWT_SECRET="dev-secret-change-in-production"
        log_warn "Using default JWT_SECRET (set JWT_SECRET env var for production)"
    fi

    # Set daemon metrics URL for backend to connect to
    if [ -z "${DAEMON_METRICS_URL:-}" ]; then
        export DAEMON_METRICS_URL="http://localhost:${DAEMON_METRICS_PORT}"
        log_info "Set DAEMON_METRICS_URL=${DAEMON_METRICS_URL}"
    fi

    # Start backend in background from web directory (for relative paths)
    cd "${PROJECT_ROOT}/web"
    nohup "$BACKEND_BINARY" \
        > "${LOG_DIR}/backend.log" 2>&1 &

    local backend_pid=$!
    echo "$backend_pid" > "$BACKEND_PID_FILE"

    cd "$PROJECT_ROOT"

    # Wait for backend to start
    sleep 2

    if ! ps -p "$backend_pid" &> /dev/null; then
        log_error "Backend failed to start"
        if [ -f "${LOG_DIR}/backend.log" ]; then
            echo "Last 10 lines of backend log:"
            tail -10 "${LOG_DIR}/backend.log" | sed 's/^/  /'
        fi
        return 1
    fi

    log_success "Backend started (PID: $backend_pid)"
    return 0
}

wait_for_health() {
    if [ "$SKIP_HEALTH_CHECK" = "true" ]; then
        log_info "Skipping health checks (--skip-health-check)"
        return 0
    fi

    if ! command -v curl &> /dev/null; then
        log_warn "curl not available, skipping health checks"
        return 0
    fi

    log_info "Running health checks..."
    echo ""

    # Check daemon metrics
    log_info "Checking daemon metrics endpoint..."
    local daemon_ready=false
    for i in {1..15}; do
        if curl -sf "http://localhost:${DAEMON_METRICS_PORT}/metrics" > /dev/null 2>&1; then
            daemon_ready=true
            break
        fi
        sleep 2
    done

    if [ "$daemon_ready" = "true" ]; then
        log_success "✓ Daemon metrics: http://localhost:${DAEMON_METRICS_PORT}/metrics"
    else
        log_warn "✗ Daemon metrics not responding (may still be initializing)"
    fi

    # Check backend health
    log_info "Checking backend API endpoint..."
    local backend_ready=false
    for i in {1..15}; do
        if curl -skf "https://localhost:${BACKEND_PORT}/api/v1/health" > /dev/null 2>&1; then
            backend_ready=true
            break
        fi
        sleep 2
    done

    if [ "$backend_ready" = "true" ]; then
        log_success "✓ Backend API: https://localhost:${BACKEND_PORT}/api/v1/health"
    else
        log_warn "✗ Backend API not responding (may still be initializing)"
    fi

    echo ""

    if [ "$daemon_ready" = "true" ] && [ "$backend_ready" = "true" ]; then
        return 0
    else
        log_warn "Some health checks failed, but services may still be starting"
        return 0  # Don't fail startup
    fi
}

show_summary() {
    echo ""
    log_success "StorageSage started successfully!"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  Services Running:"
    echo "    ✓ Storage-Sage Daemon"
    echo "    ✓ Storage-Sage Backend API"
    echo "    ✓ Storage-Sage Frontend UI"
    echo ""
    echo "  Access Points:"
    echo "    Frontend/UI:  https://localhost:${BACKEND_PORT}"
    echo "    Backend API:  https://localhost:${BACKEND_PORT}/api/v1"
    echo "    Daemon Metrics: http://localhost:${DAEMON_METRICS_PORT}/metrics"
    echo ""
    echo "  Process IDs:"
    if [ -f "$DAEMON_PID_FILE" ]; then
        echo "    Daemon:  $(cat "$DAEMON_PID_FILE")"
    fi
    if [ -f "$BACKEND_PID_FILE" ]; then
        echo "    Backend: $(cat "$BACKEND_PID_FILE")"
    fi
    echo ""
    echo "  Logs:"
    echo "    Daemon:  ${LOG_DIR}/daemon.log"
    echo "    Backend: ${LOG_DIR}/backend.log"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Useful commands:"
    echo "  View daemon logs:  tail -f ${LOG_DIR}/daemon.log"
    echo "  View backend logs: tail -f ${LOG_DIR}/backend.log"
    echo "  Check status:      ps aux | grep storage-sage"
    echo "  Stop all:          ${SCRIPT_DIR}/stop-all.sh"
    echo "  Restart all:       ${SCRIPT_DIR}/restart-all.sh"
    echo ""
}

run_foreground() {
    log_info "Running in foreground mode (Ctrl+C to stop)..."
    echo ""

    # Set environment variables for backend
    export JWT_SECRET="${JWT_SECRET:-dev-secret-change-in-production}"
    export DAEMON_METRICS_URL="${DAEMON_METRICS_URL:-http://localhost:${DAEMON_METRICS_PORT}}"

    # Start daemon
    "$DAEMON_BINARY" --config "$DAEMON_CONFIG" 2>&1 | sed 's/^/[daemon] /' &
    local daemon_pid=$!

    # Start backend
    cd "${PROJECT_ROOT}/web"
    "$BACKEND_BINARY" 2>&1 | sed 's/^/[backend] /' &
    local backend_pid=$!
    cd "$PROJECT_ROOT"

    # Wait for both processes
    wait $daemon_pid $backend_pid
}

cleanup_on_exit() {
    log_info "Cleaning up..."
    if [ -f "$DAEMON_PID_FILE" ]; then
        kill "$(cat "$DAEMON_PID_FILE")" 2>/dev/null || true
        rm -f "$DAEMON_PID_FILE"
    fi
    if [ -f "$BACKEND_PID_FILE" ]; then
        kill "$(cat "$BACKEND_PID_FILE")" 2>/dev/null || true
        rm -f "$BACKEND_PID_FILE"
    fi
}

main() {
    show_banner

    parse_args "$@"

    cd "$PROJECT_ROOT"

    # Validation
    validate_environment || exit 1
    echo ""

    # Build check
    if [ "$AUTO_BUILD" = "true" ]; then
        if ! check_build_artifacts; then
            build_all || exit 1
        else
            log_info "Build artifacts up to date (use --no-build to skip check)"
        fi
        echo ""
    else
        log_info "Skipping build (--no-build specified)"
        if ! check_build_artifacts; then
            log_error "Build artifacts missing. Run ./scripts/build-all.sh first"
            exit 1
        fi
        echo ""
    fi

    # Setup
    setup_directories
    stop_existing_processes
    echo ""

    # Foreground mode
    if [ "$FOREGROUND" = "true" ]; then
        trap cleanup_on_exit EXIT INT TERM
        run_foreground
        exit 0
    fi

    # Background mode
    start_daemon || exit 1
    start_backend || exit 1
    echo ""

    wait_for_health
    show_summary
}

main "$@"
