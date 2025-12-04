#!/bin/bash
# StorageSage Status Script v1.0
# Checks daemon status across all deployment modes and shows diagnostics
#
# Usage: ./scripts/status.sh [OPTIONS]

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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Paths
PID_FILE="${STORAGE_SAGE_PID_FILE:-/var/run/storage-sage.pid}"
CONFIG_PATH="${STORAGE_SAGE_CONFIG:-/etc/storage-sage/config.yaml}"
CONFIG_PATH_LOCAL="${PROJECT_ROOT}/web/config/config.yaml"
LOG_DIR="${STORAGE_SAGE_LOG_DIR:-/var/log/storage-sage}"
DB_DIR="${STORAGE_SAGE_DB_DIR:-/var/lib/storage-sage}"
SERVICE_NAME="storage-sage"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
DOCKER_SERVICE_NAME="storage-sage-daemon"

# Options
VERBOSE=false
SHOW_LOGS=false
LOG_LINES=20
JSON_OUTPUT=false

# State
DAEMON_RUNNING=false
DAEMON_MODE=""
DAEMON_PID=""
METRICS_PORT=9090
METRICS_ENDPOINT=""

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    if [ "$JSON_OUTPUT" = true ]; then
        return
    fi

    local level="$1"
    shift
    local message="$*"

    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        OK|SUCCESS)
            echo -e "${GREEN}[✓]${NC} $message"
            ;;
        WARN|WARNING)
            echo -e "${YELLOW}[!]${NC} $message"
            ;;
        ERROR|FAIL)
            echo -e "${RED}[✗]${NC} $message"
            ;;
        DEBUG)
            if [ "$VERBOSE" = true ]; then
                echo -e "${CYAN}[DEBUG]${NC} $message"
            fi
            ;;
        HEADER)
            echo -e "${CYAN}$message${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Checks the status of the StorageSage daemon across all deployment modes.

OPTIONS:
  -h, --help      Show this help message
  -v, --verbose   Show detailed information
  -l, --logs      Show recent log entries
  -n, --lines N   Number of log lines to show (default: 20)
  -j, --json      Output status in JSON format
  -w, --watch     Continuously watch status (updates every 2s)

EXAMPLES:
  # Check basic status
  $0

  # Show detailed status with recent logs
  $0 --verbose --logs

  # Output machine-readable JSON
  $0 --json

  # Continuously monitor status
  $0 --watch

EOF
}

# ============================================================================
# DETECTION FUNCTIONS
# ============================================================================

detect_config() {
    if [ -f "$CONFIG_PATH" ]; then
        echo "$CONFIG_PATH"
    elif [ -f "$CONFIG_PATH_LOCAL" ]; then
        echo "$CONFIG_PATH_LOCAL"
    else
        echo ""
    fi
}

get_metrics_port() {
    local config
    config=$(detect_config)

    if [ -z "$config" ]; then
        echo "9090"
        return
    fi

    if command -v python3 &> /dev/null; then
        METRICS_PORT=$(python3 -c "import yaml; c=yaml.safe_load(open('$config')); print(c.get('prometheus', {}).get('port', 9090))" 2>/dev/null || echo "9090")
    fi

    echo "$METRICS_PORT"
}

check_systemd() {
    if ! command -v systemctl &> /dev/null; then
        return 1
    fi

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        DAEMON_RUNNING=true
        DAEMON_MODE="systemd"
        DAEMON_PID=$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        return 0
    fi

    return 1
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi

    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        return 1
    fi

    cd "$PROJECT_ROOT"
    local container_id
    container_id=$(docker compose ps -q "$DOCKER_SERVICE_NAME" 2>/dev/null || true)

    if [ -n "$container_id" ]; then
        # Check if actually running
        if docker ps -q -f id="$container_id" | grep -q .; then
            DAEMON_RUNNING=true
            DAEMON_MODE="docker"
            DAEMON_PID="$container_id"
            return 0
        fi
    fi

    return 1
}

check_direct() {
    # Check PID file
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" &> /dev/null; then
            DAEMON_RUNNING=true
            DAEMON_MODE="direct (PID file)"
            DAEMON_PID="$pid"
            return 0
        fi
    fi

    # Check by process name
    local pids
    pids=$(pgrep -f "storage-sage.*--config" 2>/dev/null || true)

    if [ -n "$pids" ]; then
        DAEMON_RUNNING=true
        DAEMON_MODE="direct (process)"
        DAEMON_PID=$(echo "$pids" | head -1)
        return 0
    fi

    return 1
}

detect_daemon_status() {
    # Try detection in order of preference
    if check_systemd; then
        return 0
    elif check_docker; then
        return 0
    elif check_direct; then
        return 0
    fi

    DAEMON_RUNNING=false
    DAEMON_MODE="not running"
    return 1
}

# ============================================================================
# METRICS FUNCTIONS
# ============================================================================

get_metrics_stats() {
    if ! curl -sf "$METRICS_ENDPOINT" > /dev/null 2>&1; then
        echo "unavailable"
        return 1
    fi

    local metrics
    metrics=$(curl -sf "$METRICS_ENDPOINT" 2>/dev/null || echo "")

    if [ -z "$metrics" ]; then
        echo "unavailable"
        return 1
    fi

    echo "available"
    return 0
}

get_metric_value() {
    local metric_name="$1"
    local default="${2:-0}"

    if ! curl -sf "$METRICS_ENDPOINT" > /dev/null 2>&1; then
        echo "$default"
        return
    fi

    local value
    value=$(curl -sf "$METRICS_ENDPOINT" 2>/dev/null | grep "^${metric_name}" | grep -v "^#" | awk '{print $2}' | head -1 || echo "$default")

    echo "${value:-$default}"
}

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

show_basic_status() {
    echo ""
    log HEADER "========================================"
    log HEADER "  StorageSage Daemon Status"
    log HEADER "========================================"
    echo ""

    if [ "$DAEMON_RUNNING" = true ]; then
        log SUCCESS "Daemon is RUNNING"
        echo ""
        echo "  Mode: $DAEMON_MODE"
        echo "  PID: $DAEMON_PID"

        # Get uptime for direct/systemd modes
        case "$DAEMON_MODE" in
            systemd)
                local uptime
                uptime=$(systemctl show -p ActiveEnterTimestamp --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
                if [ "$uptime" != "unknown" ]; then
                    echo "  Started: $uptime"
                fi
                ;;
            direct*)
                if [ -n "$DAEMON_PID" ] && [ "$DAEMON_PID" != "unknown" ]; then
                    local start_time
                    start_time=$(ps -p "$DAEMON_PID" -o lstart= 2>/dev/null || echo "unknown")
                    if [ "$start_time" != "unknown" ]; then
                        echo "  Started: $start_time"
                    fi
                fi
                ;;
            docker)
                local container_status
                container_status=$(docker inspect --format='{{.State.Status}}' "$DAEMON_PID" 2>/dev/null || echo "unknown")
                echo "  Container Status: $container_status"

                local start_time
                start_time=$(docker inspect --format='{{.State.StartedAt}}' "$DAEMON_PID" 2>/dev/null || echo "unknown")
                if [ "$start_time" != "unknown" ]; then
                    echo "  Started: $start_time"
                fi
                ;;
        esac

        # Check metrics endpoint
        echo ""
        echo "  Metrics Endpoint: $METRICS_ENDPOINT"
        local metrics_status
        metrics_status=$(get_metrics_stats)
        echo "  Metrics Status: $metrics_status"

        # Get config location
        local config
        config=$(detect_config)
        if [ -n "$config" ]; then
            echo "  Config: $config"
        fi

    else
        log ERROR "Daemon is NOT RUNNING"
        echo ""
        echo "  No active daemon process found"
        echo ""
        echo "  To start the daemon:"
        echo "    ${SCRIPT_DIR}/start.sh"
    fi

    echo ""
}

show_detailed_status() {
    show_basic_status

    if [ "$DAEMON_RUNNING" = false ]; then
        return
    fi

    log HEADER "Detailed Information:"
    log HEADER "========================================"
    echo ""

    # Config details
    local config
    config=$(detect_config)
    if [ -n "$config" ] && [ -f "$config" ]; then
        echo "Configuration:"
        echo "  Path: $config"
        echo "  Size: $(du -h "$config" | cut -f1)"
        echo "  Modified: $(stat -c %y "$config" 2>/dev/null | cut -d'.' -f1)"
        echo ""
    fi

    # Log details
    local log_file="${LOG_DIR}/cleanup.log"
    if [ -f "$log_file" ]; then
        echo "Logging:"
        echo "  Log File: $log_file"
        echo "  Size: $(du -h "$log_file" | cut -f1)"
        echo "  Modified: $(stat -c %y "$log_file" 2>/dev/null | cut -d'.' -f1)"
        echo ""
    fi

    # Database details
    local db_file="${DB_DIR}/deletions.db"
    if [ -f "$db_file" ]; then
        echo "Database:"
        echo "  Path: $db_file"
        echo "  Size: $(du -h "$db_file" | cut -f1)"
        echo "  Modified: $(stat -c %y "$db_file" 2>/dev/null | cut -d'.' -f1)"
        echo ""
    fi

    # Metrics details
    if [ "$(get_metrics_stats)" = "available" ]; then
        echo "Metrics:"
        echo "  Endpoint: $METRICS_ENDPOINT"

        local files_deleted
        files_deleted=$(get_metric_value "storagesage_files_deleted_total" "0")
        echo "  Files Deleted (total): $files_deleted"

        local bytes_freed
        bytes_freed=$(get_metric_value "storagesage_bytes_freed_total" "0")
        if command -v numfmt &> /dev/null; then
            bytes_freed=$(numfmt --to=iec-i --suffix=B "$bytes_freed" 2>/dev/null || echo "$bytes_freed bytes")
        fi
        echo "  Bytes Freed (total): $bytes_freed"

        local scan_errors
        scan_errors=$(get_metric_value "storagesage_scan_errors_total" "0")
        echo "  Scan Errors: $scan_errors"

        echo ""
    fi

    # Process details (direct/systemd only)
    if [ "$DAEMON_MODE" != "docker" ] && [ -n "$DAEMON_PID" ] && [ "$DAEMON_PID" != "unknown" ]; then
        echo "Process:"
        echo "  PID: $DAEMON_PID"

        local cpu_usage
        cpu_usage=$(ps -p "$DAEMON_PID" -o %cpu= 2>/dev/null | tr -d ' ' || echo "unknown")
        echo "  CPU: ${cpu_usage}%"

        local mem_usage
        mem_usage=$(ps -p "$DAEMON_PID" -o %mem= 2>/dev/null | tr -d ' ' || echo "unknown")
        echo "  Memory: ${mem_usage}%"

        local rss
        rss=$(ps -p "$DAEMON_PID" -o rss= 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$rss" != "0" ] && command -v numfmt &> /dev/null; then
            rss=$(numfmt --to=iec-i --suffix=B --from-unit=1024 "$rss" 2>/dev/null || echo "${rss}K")
        else
            rss="${rss}K"
        fi
        echo "  RSS: $rss"

        echo ""
    fi

    # Docker-specific details
    if [ "$DAEMON_MODE" = "docker" ]; then
        echo "Container:"
        echo "  ID: $DAEMON_PID"
        echo "  Name: $DOCKER_SERVICE_NAME"

        local container_image
        container_image=$(docker inspect --format='{{.Config.Image}}' "$DAEMON_PID" 2>/dev/null || echo "unknown")
        echo "  Image: $container_image"

        local restart_count
        restart_count=$(docker inspect --format='{{.RestartCount}}' "$DAEMON_PID" 2>/dev/null || echo "0")
        echo "  Restart Count: $restart_count"

        # Container stats
        if docker stats --no-stream "$DAEMON_PID" &> /dev/null; then
            local stats
            stats=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" "$DAEMON_PID" 2>/dev/null | tail -1)
            if [ -n "$stats" ]; then
                echo ""
                echo "  Stats:"
                echo "    CPU: $(echo "$stats" | awk '{print $1}')"
                echo "    Memory: $(echo "$stats" | awk '{print $2}')"
                echo "    Network I/O: $(echo "$stats" | awk '{print $3}')"
                echo "    Disk I/O: $(echo "$stats" | awk '{print $4}')"
            fi
        fi

        echo ""
    fi

    # Systemd-specific details
    if [ "$DAEMON_MODE" = "systemd" ]; then
        echo "Systemd Service:"
        echo "  Name: $SERVICE_NAME"

        local load_state
        load_state=$(systemctl show -p LoadState --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        echo "  Load State: $load_state"

        local active_state
        active_state=$(systemctl show -p ActiveState --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        echo "  Active State: $active_state"

        local sub_state
        sub_state=$(systemctl show -p SubState --value "$SERVICE_NAME" 2>/dev/null || echo "unknown")
        echo "  Sub State: $sub_state"

        echo ""
    fi
}

show_logs() {
    if [ "$DAEMON_RUNNING" = false ]; then
        log WARN "Daemon not running, showing last available logs..."
    fi

    echo ""
    log HEADER "Recent Logs (last $LOG_LINES lines):"
    log HEADER "========================================"
    echo ""

    case "$DAEMON_MODE" in
        systemd)
            sudo journalctl -u "$SERVICE_NAME" -n "$LOG_LINES" --no-pager 2>/dev/null || \
                log ERROR "Failed to retrieve systemd logs"
            ;;
        docker)
            docker compose logs --tail="$LOG_LINES" "$DOCKER_SERVICE_NAME" 2>/dev/null || \
                log ERROR "Failed to retrieve Docker logs"
            ;;
        *)
            local log_file="${LOG_DIR}/cleanup.log"
            if [ -f "$log_file" ]; then
                tail -n "$LOG_LINES" "$log_file"
            else
                log WARN "Log file not found: $log_file"
            fi
            ;;
    esac

    echo ""
}

show_json_status() {
    detect_daemon_status > /dev/null 2>&1

    local config
    config=$(detect_config)

    local metrics_status
    metrics_status=$(get_metrics_stats)

    cat <<EOF
{
  "daemon": {
    "running": $([ "$DAEMON_RUNNING" = true ] && echo "true" || echo "false"),
    "mode": "$DAEMON_MODE",
    "pid": "$DAEMON_PID"
  },
  "config": {
    "path": "$config",
    "exists": $([ -f "$config" ] && echo "true" || echo "false")
  },
  "metrics": {
    "endpoint": "$METRICS_ENDPOINT",
    "status": "$metrics_status",
    "port": $METRICS_PORT
  },
  "paths": {
    "log_dir": "$LOG_DIR",
    "db_dir": "$DB_DIR",
    "pid_file": "$PID_FILE"
  }
}
EOF
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -l|--logs)
                SHOW_LOGS=true
                shift
                ;;
            -n|--lines)
                LOG_LINES="$2"
                shift 2
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -w|--watch)
                # Watch mode - continuously update status
                while true; do
                    clear
                    "$0" --verbose --logs
                    sleep 2
                done
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

    # Get metrics port
    METRICS_PORT=$(get_metrics_port)
    METRICS_ENDPOINT="http://localhost:${METRICS_PORT}/metrics"

    # JSON output mode
    if [ "$JSON_OUTPUT" = true ]; then
        show_json_status
        exit 0
    fi

    # Detect daemon status
    detect_daemon_status > /dev/null 2>&1

    # Show status based on verbosity
    if [ "$VERBOSE" = true ]; then
        show_detailed_status
    else
        show_basic_status
    fi

    # Show logs if requested
    if [ "$SHOW_LOGS" = true ]; then
        show_logs
    fi

    # Exit with appropriate code
    if [ "$DAEMON_RUNNING" = true ]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
