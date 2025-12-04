#!/bin/bash
# StorageSage Unified Stop Script
# Stops all running StorageSage processes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PID_DIR="${PROJECT_ROOT}/.pids"
DAEMON_PID_FILE="${PID_DIR}/daemon.pid"
BACKEND_PID_FILE="${PID_DIR}/backend.pid"

FORCE="${FORCE:-false}"

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

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -h, --help    Show this help message
  --force       Force kill processes (SIGKILL)

EXAMPLES:
  # Stop all services gracefully
  $0

  # Force kill all services
  $0 --force

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --force)
                FORCE="true"
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

stop_process() {
    local name="$1"
    local pid_file="$2"

    if [ ! -f "$pid_file" ]; then
        log_info "$name: no PID file found"
        return 0
    fi

    local pid
    pid=$(cat "$pid_file")

    if ! ps -p "$pid" &> /dev/null; then
        log_warn "$name: process not running (stale PID file)"
        rm -f "$pid_file"
        return 0
    fi

    log_info "Stopping $name (PID: $pid)..."

    if [ "$FORCE" = "true" ]; then
        kill -9 "$pid" 2>/dev/null || true
        log_warn "$name: force killed (SIGKILL)"
    else
        kill "$pid" 2>/dev/null || true

        # Wait up to 10 seconds for graceful shutdown
        local waited=0
        while ps -p "$pid" &> /dev/null && [ $waited -lt 10 ]; do
            sleep 1
            waited=$((waited + 1))
        done

        if ps -p "$pid" &> /dev/null; then
            log_warn "$name: didn't stop gracefully, force killing..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi

    # Verify stopped
    if ps -p "$pid" &> /dev/null; then
        log_error "$name: failed to stop (PID: $pid still running)"
        return 1
    else
        log_success "$name: stopped"
        rm -f "$pid_file"
        return 0
    fi
}

stop_by_name() {
    local pattern="$1"
    local name="$2"

    local pids
    pids=$(pgrep -f "$pattern" 2>/dev/null || true)

    if [ -z "$pids" ]; then
        return 0
    fi

    log_info "Found additional $name processes: $pids"

    for pid in $pids; do
        if ps -p "$pid" &> /dev/null; then
            log_info "Stopping $name (PID: $pid)..."
            if [ "$FORCE" = "true" ]; then
                kill -9 "$pid" 2>/dev/null || true
            else
                kill "$pid" 2>/dev/null || true
            fi
        fi
    done
}

main() {
    parse_args "$@"

    echo "Stopping all StorageSage services..."
    echo ""

    local errors=0

    # Stop backend
    if ! stop_process "Backend" "$BACKEND_PID_FILE"; then
        errors=$((errors + 1))
    fi

    # Stop daemon
    if ! stop_process "Daemon" "$DAEMON_PID_FILE"; then
        errors=$((errors + 1))
    fi

    # Check for any remaining processes
    log_info "Checking for orphaned processes..."
    stop_by_name "build/storage-sage-web" "backend"
    stop_by_name "build/storage-sage[^-]" "daemon"

    echo ""

    if [ $errors -gt 0 ]; then
        log_warn "Stopped with $errors error(s)"
        exit 1
    else
        log_success "All StorageSage services stopped"
        exit 0
    fi
}

main "$@"
