#!/bin/bash
# StorageSage Stop Script v1.0
# Safely stops the StorageSage daemon across all deployment modes
#
# Usage: ./scripts/stop.sh [OPTIONS]

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
PID_FILE="${STORAGE_SAGE_PID_FILE:-/var/run/storage-sage.pid}"
SERVICE_NAME="storage-sage"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
DOCKER_SERVICE_NAME="storage-sage-daemon"

# Options
FORCE=false
WAIT_TIMEOUT=30
VERBOSE=false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"

    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        OK|SUCCESS)
            echo -e "${GREEN}[OK]${NC} $message"
            ;;
        WARN|WARNING)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR|FAIL)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        DEBUG)
            if [ "$VERBOSE" = true ]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
            fi
            ;;
        *)
            echo "$message"
            ;;
    esac
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Stops the StorageSage daemon in all deployment modes.

OPTIONS:
  -h, --help      Show this help message
  -f, --force     Force kill if graceful shutdown fails
  -w, --wait N    Wait up to N seconds for shutdown (default: 30)
  -v, --verbose   Verbose output

EXAMPLES:
  # Stop daemon gracefully
  $0

  # Force stop if not responding
  $0 --force

  # Wait up to 60 seconds before giving up
  $0 --wait 60

EOF
}

# ============================================================================
# STOP FUNCTIONS
# ============================================================================

stop_by_pid_file() {
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ! ps -p "$pid" &> /dev/null; then
        log WARN "PID file exists but process not running (stale)"
        rm -f "$PID_FILE"
        return 1
    fi

    log INFO "Stopping daemon (PID: $pid)..."

    # Try graceful shutdown first (SIGTERM)
    if kill -TERM "$pid" 2>/dev/null; then
        log DEBUG "Sent SIGTERM to PID $pid"

        # Wait for process to exit
        local elapsed=0
        while ps -p "$pid" &> /dev/null && [ $elapsed -lt $WAIT_TIMEOUT ]; do
            sleep 1
            elapsed=$((elapsed + 1))
            if [ $((elapsed % 5)) -eq 0 ]; then
                log DEBUG "Waiting for shutdown... (${elapsed}s)"
            fi
        done

        if ps -p "$pid" &> /dev/null; then
            if [ "$FORCE" = true ]; then
                log WARN "Graceful shutdown failed, force killing..."
                kill -KILL "$pid" 2>/dev/null || true
                sleep 1
            else
                log ERROR "Process did not stop within ${WAIT_TIMEOUT}s"
                log INFO "Use --force to force kill, or increase --wait timeout"
                return 1
            fi
        fi
    else
        log WARN "Failed to send SIGTERM (already stopped?)"
    fi

    # Verify stopped
    if ! ps -p "$pid" &> /dev/null; then
        log OK "Daemon stopped successfully"
        rm -f "$PID_FILE"
        return 0
    else
        log ERROR "Failed to stop daemon"
        return 1
    fi
}

stop_by_process_name() {
    local pids
    pids=$(pgrep -f "storage-sage.*--config" || true)

    if [ -z "$pids" ]; then
        return 1
    fi

    log INFO "Found StorageSage process(es): $pids"

    for pid in $pids; do
        log INFO "Stopping PID $pid..."

        if kill -TERM "$pid" 2>/dev/null; then
            log DEBUG "Sent SIGTERM to PID $pid"

            # Wait for process to exit
            local elapsed=0
            while ps -p "$pid" &> /dev/null && [ $elapsed -lt $WAIT_TIMEOUT ]; do
                sleep 1
                elapsed=$((elapsed + 1))
            done

            if ps -p "$pid" &> /dev/null; then
                if [ "$FORCE" = true ]; then
                    log WARN "Graceful shutdown failed, force killing PID $pid..."
                    kill -KILL "$pid" 2>/dev/null || true
                else
                    log ERROR "PID $pid did not stop within ${WAIT_TIMEOUT}s"
                    continue
                fi
            fi

            if ! ps -p "$pid" &> /dev/null; then
                log OK "Stopped PID $pid"
            fi
        fi
    done

    # Clean up PID file if it exists
    rm -f "$PID_FILE"

    return 0
}

stop_docker() {
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        return 1
    fi

    if ! command -v docker &> /dev/null; then
        return 1
    fi

    # Check if container is running
    cd "$PROJECT_ROOT"
    local container_id
    container_id=$(docker compose ps -q "$DOCKER_SERVICE_NAME" 2>/dev/null || true)

    if [ -z "$container_id" ]; then
        return 1
    fi

    log INFO "Stopping Docker container: $DOCKER_SERVICE_NAME"

    if docker compose stop -t "$WAIT_TIMEOUT" "$DOCKER_SERVICE_NAME" 2>&1 | tee /dev/null; then
        log OK "Docker container stopped"

        if [ "$FORCE" = true ]; then
            log INFO "Removing container..."
            docker compose rm -f "$DOCKER_SERVICE_NAME" 2>&1 | tee /dev/null
        fi

        return 0
    else
        log ERROR "Failed to stop Docker container"

        if [ "$FORCE" = true ]; then
            log WARN "Force killing container..."
            docker compose kill "$DOCKER_SERVICE_NAME" 2>&1 | tee /dev/null
            docker compose rm -f "$DOCKER_SERVICE_NAME" 2>&1 | tee /dev/null
            return 0
        fi

        return 1
    fi
}

stop_systemd() {
    if ! command -v systemctl &> /dev/null; then
        return 1
    fi

    if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 1
    fi

    log INFO "Stopping systemd service: $SERVICE_NAME"

    if sudo systemctl stop "$SERVICE_NAME" 2>&1 | tee /dev/null; then
        # Wait for service to stop
        local elapsed=0
        while systemctl is-active --quiet "$SERVICE_NAME" && [ $elapsed -lt $WAIT_TIMEOUT ]; do
            sleep 1
            elapsed=$((elapsed + 1))
        done

        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log ERROR "Service did not stop within ${WAIT_TIMEOUT}s"

            if [ "$FORCE" = true ]; then
                log WARN "Force killing service..."
                sudo systemctl kill -s KILL "$SERVICE_NAME" 2>&1 | tee /dev/null
            else
                return 1
            fi
        fi

        log OK "Systemd service stopped"
        return 0
    else
        log ERROR "Failed to stop systemd service"
        return 1
    fi
}

# ============================================================================
# MAIN STOP LOGIC
# ============================================================================

stop_daemon() {
    log INFO "Attempting to stop StorageSage daemon..."
    echo ""

    local stopped=false

    # Try each method in order of preference
    # 1. Systemd (most managed)
    if stop_systemd; then
        stopped=true
    # 2. Docker (containerized)
    elif stop_docker; then
        stopped=true
    # 3. PID file (direct mode)
    elif stop_by_pid_file; then
        stopped=true
    # 4. Process name (fallback)
    elif stop_by_process_name; then
        stopped=true
    fi

    echo ""

    if [ "$stopped" = true ]; then
        log SUCCESS "StorageSage daemon stopped successfully"
        return 0
    else
        log WARN "No running StorageSage daemon found"
        log INFO "The daemon may already be stopped"
        return 0
    fi
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -w|--wait)
                WAIT_TIMEOUT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    parse_arguments "$@"
    stop_daemon
    exit $?
}

main "$@"
