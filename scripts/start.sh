#!/bin/bash
# StorageSage Startup Script v1.0
# Comprehensive daemon startup with error diagnosis and multi-mode support
#
# Usage: ./scripts/start.sh [OPTIONS]
# Modes: direct (binary), docker (compose), systemd (service)

set -euo pipefail

# ============================================================================
# CONFIGURATION AND DEFAULTS
# ============================================================================

SCRIPT_VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default paths (can be overridden by environment variables)
BINARY_PATH="${STORAGE_SAGE_BINARY:-/usr/local/bin/storage-sage}"
BINARY_PATH_LOCAL="${PROJECT_ROOT}/storage-sage"
CONFIG_PATH="${STORAGE_SAGE_CONFIG:-/etc/storage-sage/config.yaml}"
CONFIG_PATH_LOCAL="${PROJECT_ROOT}/web/config/config.yaml}"
LOG_DIR="${STORAGE_SAGE_LOG_DIR:-/var/log/storage-sage}"
DB_DIR="${STORAGE_SAGE_DB_DIR:-/var/lib/storage-sage}"
PID_FILE="${STORAGE_SAGE_PID_FILE:-/var/run/storage-sage.pid}"
STARTUP_LOG="/tmp/storage-sage-startup.log"

# Service configuration
SERVICE_NAME="storage-sage"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
DOCKER_SERVICE_NAME="storage-sage-daemon"

# Startup configuration
DEFAULT_MODE="auto"
MODE="$DEFAULT_MODE"
FOREGROUND=false
BACKGROUND=false
DRY_RUN=false
RUN_ONCE=false
CHECK_ONLY=false
VERBOSE=false
DOCKER_START_ALL=false  # Start all services in Docker mode (daemon + backend + observability)
MAX_STARTUP_WAIT=30
HEALTH_CHECK_INTERVAL=2

# Runtime state
EXIT_CODE=0
DAEMON_PID=""
METRICS_PORT=9090
METRICS_ENDPOINT=""
BACKEND_URL="https://localhost:8443"
BACKEND_HEALTH_ENDPOINT="${BACKEND_URL}/api/v1/health"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

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
                echo -e "${CYAN}[DEBUG]${NC} $message"
            fi
            ;;
        *)
            echo "$message"
            ;;
    esac

    # Also log to file
    echo "[$timestamp] [$level] $message" >> "$STARTUP_LOG"
}

show_banner() {
    echo -e "${CYAN}"
    echo "========================================"
    echo "  StorageSage Startup Script v${SCRIPT_VERSION}"
    echo "========================================"
    echo -e "${NC}"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -h, --help              Show this help message
  -c, --config PATH       Override config file path
  -m, --mode MODE         Startup mode: direct|docker|systemd (default: auto)
  -f, --foreground        Run in foreground (direct mode only)
  -b, --background        Run in background with PID file (direct mode only)
  -d, --dry-run           Start in dry-run mode (no deletions)
  --once                  Run once and exit (direct mode only)
  --all, --start-all      Start all services (daemon + backend + UI) in Docker mode
  --check-only            Run diagnostics only, don't start
  --verbose               Verbose output
  --restart               Restart if already running
  --validate-config       Validate config without starting

MODES:
  auto        Auto-detect best available mode (default)
  direct      Run binary directly
  docker      Use Docker Compose
  systemd     Use systemd service

ENVIRONMENT VARIABLES:
  STORAGE_SAGE_BINARY     Binary path (default: /usr/local/bin/storage-sage)
  STORAGE_SAGE_CONFIG     Config path (default: /etc/storage-sage/config.yaml)
  STORAGE_SAGE_LOG_DIR    Log directory (default: /var/log/storage-sage)
  STORAGE_SAGE_DB_DIR     Database directory (default: /var/lib/storage-sage)

EXAMPLES:
  # Start with auto-detected mode
  $0

  # Start in Docker mode (daemon only)
  $0 --mode docker

  # Start all services in Docker mode (daemon + backend + UI + observability)
  $0 --mode docker --all

  # Start in foreground for debugging
  $0 --mode direct --foreground --verbose

  # Validate configuration only
  $0 --validate-config

  # Run diagnostics without starting
  $0 --check-only

EOF
}

diagnose_error() {
    local error_type="$1"
    shift
    local details="$*"

    echo ""
    log ERROR "Failed to start StorageSage"
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Error: $error_type${NC}"
    echo ""

    case "$error_type" in
        "Binary not found")
            echo "Diagnosis:"
            echo "  - Searched paths:"
            echo "    * $BINARY_PATH"
            echo "    * $BINARY_PATH_LOCAL"
            echo "  - Binary exists: NO"
            echo ""
            echo "Possible causes:"
            echo "  1. StorageSage not installed"
            echo "  2. Binary installed in non-standard location"
            echo "  3. PATH environment variable incorrect"
            echo ""
            echo "Suggested fixes:"
            echo "  1. Install StorageSage:"
            echo "     cd ${PROJECT_ROOT}"
            echo "     make build"
            echo "     sudo make install"
            echo ""
            echo "  2. Or specify binary location:"
            echo "     export STORAGE_SAGE_BINARY=/path/to/storage-sage"
            echo "     $0"
            echo ""
            echo "  3. Or use Docker mode:"
            echo "     $0 --mode docker"
            ;;

        "Config not found"|"Config invalid")
            echo "Diagnosis:"
            echo "  - Searched paths:"
            echo "    * $CONFIG_PATH"
            echo "    * $CONFIG_PATH_LOCAL"
            if [ -n "$details" ]; then
                echo "  - Details: $details"
            fi
            echo ""
            echo "Possible causes:"
            echo "  1. Configuration file missing"
            echo "  2. Invalid YAML syntax"
            echo "  3. Missing required fields"
            echo ""
            echo "Suggested fixes:"
            echo "  1. Create config from template:"
            echo "     cp ${PROJECT_ROOT}/web/config/config.yaml /etc/storage-sage/"
            echo ""
            echo "  2. Validate YAML syntax:"
            echo "     yamllint $CONFIG_PATH"
            echo ""
            echo "  3. Check required fields:"
            echo "     cat $CONFIG_PATH"
            ;;

        "Permission denied")
            echo "Diagnosis:"
            echo "  - Details: $details"
            local current_user
            current_user="$(whoami)"
            local current_uid
            current_uid="$(id -u)"
            echo "  - Current user: $current_user (UID $current_uid)"
            echo ""
            echo "Possible causes:"
            echo "  1. Directory owned by different user"
            echo "  2. Insufficient permissions on directory"
            echo "  3. SELinux/AppArmor restrictions"
            echo ""
            echo "Suggested fixes:"
            echo "  1. Fix ownership of log directory:"
            echo "     sudo chown -R ${current_user}:${current_user} $LOG_DIR"
            echo ""
            echo "  2. Fix ownership of database directory:"
            echo "     sudo chown -R ${current_user}:${current_user} $DB_DIR"
            echo ""
            echo "  3. Fix permissions:"
            echo "     sudo chmod 755 $LOG_DIR $DB_DIR"
            echo ""
            echo "  4. Or run as storage-sage user:"
            echo "     sudo -u storage-sage $0"
            ;;

        "Port in use")
            echo "Diagnosis:"
            echo "  - Port: $METRICS_PORT"
            echo "  - Details: $details"
            echo ""
            # Try to find what's using the port
            if command -v lsof &> /dev/null; then
                echo "  - Process using port:"
                sudo lsof -i ":$METRICS_PORT" 2>/dev/null || echo "    Unable to determine"
            elif command -v netstat &> /dev/null; then
                echo "  - Process using port:"
                sudo netstat -tulpn | grep ":$METRICS_PORT" 2>/dev/null || echo "    Unable to determine"
            fi
            echo ""
            echo "Possible causes:"
            echo "  1. StorageSage already running"
            echo "  2. Another service using port $METRICS_PORT"
            echo "  3. Previous instance not cleaned up"
            echo ""
            echo "Suggested fixes:"
            echo "  1. Check if already running:"
            echo "     ${SCRIPT_DIR}/status.sh"
            echo ""
            echo "  2. Stop existing instance:"
            echo "     ${SCRIPT_DIR}/stop.sh"
            echo ""
            echo "  3. Change port in config:"
            echo "     vim $CONFIG_PATH"
            echo "     # Edit prometheus.port to different value"
            ;;

        "Already running")
            echo "Diagnosis:"
            echo "  - PID: $details"
            echo "  - PID file: $PID_FILE"
            echo ""
            echo "Suggested fixes:"
            echo "  1. Check status:"
            echo "     ${SCRIPT_DIR}/status.sh"
            echo ""
            echo "  2. Restart daemon:"
            echo "     $0 --restart"
            echo ""
            echo "  3. Or stop and start manually:"
            echo "     ${SCRIPT_DIR}/stop.sh"
            echo "     $0"
            ;;

        "Docker not available")
            echo "Diagnosis:"
            echo "  - Docker installed: $(command -v docker &> /dev/null && echo "YES" || echo "NO")"
            echo "  - Docker Compose installed: $(command -v docker &> /dev/null && docker compose version &> /dev/null && echo "YES" || echo "NO")"
            echo ""
            echo "Possible causes:"
            echo "  1. Docker not installed"
            echo "  2. Docker daemon not running"
            echo "  3. User not in docker group"
            echo ""
            echo "Suggested fixes:"
            echo "  1. Install Docker:"
            echo "     curl -fsSL https://get.docker.com | sh"
            echo ""
            echo "  2. Start Docker daemon:"
            echo "     sudo systemctl start docker"
            echo ""
            echo "  3. Add user to docker group:"
            echo "     sudo usermod -aG docker \$(whoami)"
            echo "     newgrp docker"
            echo ""
            echo "  4. Or use direct mode:"
            echo "     $0 --mode direct"
            ;;

        "Systemd not available")
            echo "Diagnosis:"
            echo "  - Systemd available: $(command -v systemctl &> /dev/null && echo "YES" || echo "NO")"
            echo "  - Service file exists: $([ -f "$SERVICE_FILE" ] && echo "YES" || echo "NO")"
            echo ""
            echo "Suggested fixes:"
            echo "  1. Install systemd service:"
            echo "     sudo cp ${PROJECT_ROOT}/storage-sage.service /etc/systemd/system/"
            echo "     sudo systemctl daemon-reload"
            echo ""
            echo "  2. Or use different mode:"
            echo "     $0 --mode direct"
            echo "     $0 --mode docker"
            ;;

        "Health check failed")
            echo "Diagnosis:"
            echo "  - Mode: $MODE"
            echo "  - Metrics endpoint: $METRICS_ENDPOINT"
            echo "  - Config: ${CONFIG_PATH:-not detected}"
            echo "  - Details: $details"
            echo ""

            # Check if daemon process is actually running
            local daemon_status="unknown"
            case "$MODE" in
                direct)
                    if [ -n "$DAEMON_PID" ] && ps -p "$DAEMON_PID" &> /dev/null; then
                        daemon_status="running (PID $DAEMON_PID)"
                    else
                        daemon_status="NOT RUNNING"
                    fi
                    ;;
                docker)
                    local container_id="${DAEMON_PID#docker:}"
                    if docker ps -q -f id="$container_id" 2>/dev/null | grep -q .; then
                        daemon_status="running (container $container_id)"
                    else
                        daemon_status="NOT RUNNING (container may have stopped)"
                    fi
                    ;;
                systemd)
                    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
                        daemon_status="running (systemd)"
                    else
                        daemon_status="NOT RUNNING (systemd service inactive)"
                    fi
                    ;;
            esac
            echo "  - Daemon status: $daemon_status"
            echo ""

            echo "Possible causes:"
            echo "  1. Daemon started but failed during initialization"
            echo "  2. Metrics endpoint not enabled or wrong port"
            echo "  3. Configuration error (check prometheus.port setting)"
            echo "  4. Database initialization failed"
            echo "  5. Network/firewall blocking localhost:${METRICS_PORT}"
            echo ""

            echo "Suggested fixes:"
            echo "  1. Check recent logs:"
            local log_file="${LOG_DIR}/cleanup.log"
            if [ "$MODE" = "docker" ]; then
                echo "     docker compose logs --tail=50 $DOCKER_SERVICE_NAME"
                echo ""
                echo "  Recent container logs:"
                docker compose logs --tail=10 "$DOCKER_SERVICE_NAME" 2>/dev/null | sed 's/^/     /' || echo "     (unable to retrieve logs)"
            elif [ "$MODE" = "systemd" ]; then
                echo "     journalctl -u $SERVICE_NAME -n 50"
                echo ""
                echo "  Recent service logs:"
                sudo journalctl -u "$SERVICE_NAME" -n 10 --no-pager 2>/dev/null | sed 's/^/     /' || echo "     (unable to retrieve logs)"
            else
                echo "     tail -f ${log_file}"
                if [ -f "$log_file" ]; then
                    echo ""
                    echo "  Last 10 lines from log:"
                    tail -10 "$log_file" 2>/dev/null | sed 's/^/     /' || echo "     (log file empty or unreadable)"
                fi
            fi
            echo ""
            echo "  2. Check daemon process:"
            echo "     ps aux | grep storage-sage"
            echo ""
            echo "  3. Test metrics endpoint manually:"
            echo "     curl -v $METRICS_ENDPOINT"
            echo ""
            echo "  4. Verify config port setting:"
            echo "     grep -A2 'prometheus:' ${CONFIG_PATH:-/etc/storage-sage/config.yaml}"
            echo ""
            echo "  5. Try foreground mode for debugging:"
            echo "     $0 --mode direct --foreground --verbose"
            ;;

        *)
            echo "Details: $details"
            echo ""
            echo "Check logs:"
            echo "  - Startup log: $STARTUP_LOG"
            echo "  - Application log: ${LOG_DIR}/cleanup.log"
            ;;
    esac

    echo ""
    echo "For more help, see documentation or run: $0 --help"
    echo -e "${RED}========================================${NC}"
    echo ""
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_binary() {
    log INFO "Checking for StorageSage binary..."

    if [ -f "$BINARY_PATH" ] && [ -x "$BINARY_PATH" ]; then
        log OK "Binary found: $BINARY_PATH"
        return 0
    elif [ -f "$BINARY_PATH_LOCAL" ] && [ -x "$BINARY_PATH_LOCAL" ]; then
        BINARY_PATH="$BINARY_PATH_LOCAL"
        log OK "Binary found: $BINARY_PATH"
        return 0
    else
        diagnose_error "Binary not found"
        return 1
    fi
}

check_config() {
    log INFO "Checking for configuration file..."

    local config_to_check=""

    if [ -f "$CONFIG_PATH" ]; then
        config_to_check="$CONFIG_PATH"
    elif [ -f "$CONFIG_PATH_LOCAL" ]; then
        CONFIG_PATH="$CONFIG_PATH_LOCAL"
        config_to_check="$CONFIG_PATH"
    else
        diagnose_error "Config not found"
        return 1
    fi

    log OK "Config file found: $config_to_check"

    # Validate config is readable
    if [ ! -r "$config_to_check" ]; then
        diagnose_error "Permission denied" "Config file not readable: $config_to_check"
        return 1
    fi

    # Basic YAML validation
    log DEBUG "Validating YAML syntax..."
    if command -v python3 &> /dev/null; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$config_to_check'))" 2>/dev/null; then
            local error_msg
            error_msg=$(python3 -c "import yaml; yaml.safe_load(open('$config_to_check'))" 2>&1 || true)
            diagnose_error "Config invalid" "$error_msg"
            return 1
        fi
    fi

    log OK "Config validation: passed"

    # Extract metrics port from config
    if command -v python3 &> /dev/null; then
        METRICS_PORT=$(python3 -c "import yaml; c=yaml.safe_load(open('$config_to_check')); print(c.get('prometheus', {}).get('port', 9090))" 2>/dev/null || echo "9090")
    fi

    log DEBUG "Metrics port: $METRICS_PORT"
    METRICS_ENDPOINT="http://localhost:${METRICS_PORT}/metrics"

    return 0
}

check_directories() {
    log INFO "Checking required directories..."

    # Check log directory
    if [ ! -d "$LOG_DIR" ]; then
        log WARN "Log directory doesn't exist: $LOG_DIR"
        log INFO "Creating log directory..."
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            diagnose_error "Permission denied" "Cannot create log directory: $LOG_DIR"
            return 1
        fi
    fi

    if [ ! -w "$LOG_DIR" ]; then
        diagnose_error "Permission denied" "Log directory not writable: $LOG_DIR"
        return 1
    fi

    log OK "Log directory writable: $LOG_DIR"

    # Check database directory
    if [ ! -d "$DB_DIR" ]; then
        log WARN "Database directory doesn't exist: $DB_DIR"
        log INFO "Creating database directory..."
        if ! mkdir -p "$DB_DIR" 2>/dev/null; then
            diagnose_error "Permission denied" "Cannot create database directory: $DB_DIR"
            return 1
        fi
    fi

    if [ ! -w "$DB_DIR" ]; then
        diagnose_error "Permission denied" "Database directory not writable: $DB_DIR"
        return 1
    fi

    log OK "Database directory writable: $DB_DIR"

    return 0
}

check_port_available() {
    log INFO "Checking port availability..."

    if command -v lsof &> /dev/null; then
        if sudo lsof -i ":$METRICS_PORT" &> /dev/null; then
            local process_info
            process_info=$(sudo lsof -i ":$METRICS_PORT" 2>/dev/null | tail -1)
            diagnose_error "Port in use" "$process_info"
            return 1
        fi
    elif command -v netstat &> /dev/null; then
        if sudo netstat -tulpn | grep ":$METRICS_PORT" &> /dev/null; then
            local process_info
            process_info=$(sudo netstat -tulpn | grep ":$METRICS_PORT" 2>/dev/null)
            diagnose_error "Port in use" "$process_info"
            return 1
        fi
    else
        log WARN "Cannot check port availability (lsof/netstat not found)"
        return 0
    fi

    log OK "Port $METRICS_PORT available"
    return 0
}

check_already_running() {
    log INFO "Checking for existing daemon process..."

    # Check PID file
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" &> /dev/null; then
            diagnose_error "Already running" "$pid"
            return 1
        else
            log WARN "Stale PID file found, removing..."
            rm -f "$PID_FILE"
        fi
    fi

    # Check for process by name
    if pgrep -f "storage-sage.*--config" &> /dev/null; then
        local pid
        pid=$(pgrep -f "storage-sage.*--config" | head -1)
        diagnose_error "Already running" "$pid"
        return 1
    fi

    log OK "No existing daemon process found"
    return 0
}

check_docker() {
    log INFO "Checking Docker availability..."

    if ! command -v docker &> /dev/null; then
        diagnose_error "Docker not available"
        return 1
    fi

    if ! docker compose version &> /dev/null; then
        diagnose_error "Docker not available" "Docker Compose plugin not found"
        return 1
    fi

    if ! docker info &> /dev/null; then
        diagnose_error "Docker not available" "Docker daemon not running or permission denied"
        return 1
    fi

    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        diagnose_error "Docker not available" "docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
        return 1
    fi

    log OK "Docker available and configured"
    return 0
}

check_systemd() {
    log INFO "Checking systemd availability..."

    if ! command -v systemctl &> /dev/null; then
        diagnose_error "Systemd not available" "systemctl command not found"
        return 1
    fi

    if [ ! -f "$SERVICE_FILE" ]; then
        diagnose_error "Systemd not available" "Service file not found: $SERVICE_FILE"
        return 1
    fi

    log OK "Systemd available and service file exists"
    return 0
}

detect_config_and_port() {
    # Detect config file location and extract metrics port
    # This is needed for all modes to enable health checks
    local config=""

    if [ -f "$CONFIG_PATH" ]; then
        config="$CONFIG_PATH"
    elif [ -f "$CONFIG_PATH_LOCAL" ]; then
        config="$CONFIG_PATH_LOCAL"
    fi

    if [ -n "$config" ]; then
        CONFIG_PATH="$config"
        log DEBUG "Config detected: $config"

        # Extract metrics port from config
        if command -v python3 &> /dev/null; then
            METRICS_PORT=$(python3 -c "import yaml; c=yaml.safe_load(open('$config')); print(c.get('prometheus', {}).get('port', 9090))" 2>/dev/null || echo "9090")
        fi
    fi

    METRICS_ENDPOINT="http://localhost:${METRICS_PORT}/metrics"
    log DEBUG "Metrics endpoint: $METRICS_ENDPOINT"
}

run_preflight_checks() {
    log INFO "Running pre-flight checks..."
    echo ""

    if [ "$MODE" = "docker" ]; then
        check_docker || return 1
        # Still need to detect config for metrics port
        detect_config_and_port
    elif [ "$MODE" = "systemd" ]; then
        check_systemd || return 1
        # Still need to detect config for metrics port
        detect_config_and_port
    else
        # Direct mode checks
        check_binary || return 1
        check_config || return 1
        check_directories || return 1
        check_port_available || return 1
        check_already_running || return 1
    fi

    echo ""
    log SUCCESS "All pre-flight checks passed"
    echo ""
    return 0
}

# ============================================================================
# MODE DETECTION
# ============================================================================

detect_mode() {
    log INFO "Auto-detecting startup mode..."

    # Prefer systemd if available
    if command -v systemctl &> /dev/null && [ -f "$SERVICE_FILE" ]; then
        MODE="systemd"
        log OK "Detected mode: systemd"
        return 0
    fi

    # Try Docker next
    if command -v docker &> /dev/null && docker compose version &> /dev/null && [ -f "$DOCKER_COMPOSE_FILE" ]; then
        MODE="docker"
        log OK "Detected mode: docker"
        return 0
    fi

    # Fall back to direct
    if [ -f "$BINARY_PATH" ] || [ -f "$BINARY_PATH_LOCAL" ]; then
        MODE="direct"
        log OK "Detected mode: direct"
        return 0
    fi

    log ERROR "Could not detect suitable startup mode"
    return 1
}

# ============================================================================
# STARTUP MODES
# ============================================================================

start_direct() {
    log INFO "Starting StorageSage daemon (direct mode)..."
    log INFO "=========================================="

    local cmd="$BINARY_PATH --config $CONFIG_PATH"

    if [ "$DRY_RUN" = true ]; then
        cmd="$cmd --dry-run"
    fi

    if [ "$RUN_ONCE" = true ]; then
        cmd="$cmd --once"
    fi

    log INFO "Command: $cmd"
    echo ""

    if [ "$FOREGROUND" = true ]; then
        log INFO "Running in foreground mode (Ctrl+C to stop)..."
        echo ""
        exec $cmd
    else
        # Background mode
        log INFO "Starting in background..."

        # Start daemon in background
        nohup $cmd > "${LOG_DIR}/daemon-output.log" 2>&1 &
        DAEMON_PID=$!

        # Save PID
        echo "$DAEMON_PID" > "$PID_FILE"
        log DEBUG "PID saved to $PID_FILE"

        # Wait a moment for startup
        sleep 2

        # Check if still running
        if ! ps -p "$DAEMON_PID" &> /dev/null; then
            log ERROR "Daemon failed to start"
            if [ -f "${LOG_DIR}/daemon-output.log" ]; then
                echo "Last 10 lines of output:"
                tail -10 "${LOG_DIR}/daemon-output.log" | sed 's/^/  /'
            fi
            return 1
        fi

        log OK "Daemon started with PID: $DAEMON_PID"
        return 0
    fi
}

detect_docker_services() {
    # Detect available services in docker-compose.yml
    local available_services
    available_services=$(docker compose config --services 2>/dev/null || echo "")

    if [ -z "$available_services" ]; then
        log WARN "Unable to detect Docker Compose services"
        return 1
    fi

    log DEBUG "Available services: $available_services"
    echo "$available_services"
}

start_docker() {
    if [ "$DOCKER_START_ALL" = true ]; then
        log INFO "Starting all StorageSage services (Docker mode)..."
    else
        log INFO "Starting StorageSage daemon (Docker mode)..."
    fi
    log INFO "=========================================="

    cd "$PROJECT_ROOT"

    local services_to_start=""
    local critical_services="storage-sage-daemon"
    local optional_services=""

    if [ "$DOCKER_START_ALL" = true ]; then
        # Detect available services
        local available_services
        available_services=$(detect_docker_services)

        # Build list of services to start
        services_to_start="storage-sage-daemon"

        # Add backend (critical for --all mode)
        if echo "$available_services" | grep -q "storage-sage-backend"; then
            services_to_start="$services_to_start storage-sage-backend"
            critical_services="$critical_services storage-sage-backend"
        else
            log WARN "Backend service not found in docker-compose.yml"
        fi

        # Add observability stack (optional)
        if echo "$available_services" | grep -q "loki"; then
            services_to_start="$services_to_start loki"
            optional_services="$optional_services loki"
        fi

        if echo "$available_services" | grep -q "promtail"; then
            services_to_start="$services_to_start promtail"
            optional_services="$optional_services promtail"
        fi

        log INFO "Services to start: $services_to_start"
    else
        services_to_start="$DOCKER_SERVICE_NAME"
    fi

    log INFO "Running: docker compose up -d $services_to_start"
    echo ""

    if ! docker compose up -d $services_to_start 2>&1 | tee -a "$STARTUP_LOG"; then
        log ERROR "Docker Compose failed"
        echo ""
        log INFO "Checking container logs..."
        for service in $critical_services; do
            echo ""
            log INFO "Logs for $service:"
            docker compose logs --tail=20 "$service" 2>&1 | sed 's/^/  /'
        done
        return 1
    fi

    echo ""

    # Wait for services to initialize
    if [ "$DOCKER_START_ALL" = true ]; then
        log INFO "Waiting for services to initialize (10s)..."
        sleep 10
    else
        sleep 2
    fi

    # Verify all critical services are running
    log INFO "Verifying service status..."
    echo ""

    local all_running=true
    for service in $critical_services; do
        local container_id
        container_id=$(docker compose ps -q "$service" 2>/dev/null || echo "")

        if [ -z "$container_id" ]; then
            log ERROR "Service not found: $service"
            all_running=false
            continue
        fi

        if docker ps -q -f id="$container_id" | grep -q .; then
            local status
            status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")
            if [ "$status" = "running" ]; then
                log OK "Service running: $service (${container_id:0:12})"
            else
                log ERROR "Service not running: $service (status: $status)"
                all_running=false
            fi
        else
            log ERROR "Container not running: $service"
            all_running=false
        fi
    done

    # Check optional services (don't fail if they're not running)
    for service in $optional_services; do
        local container_id
        container_id=$(docker compose ps -q "$service" 2>/dev/null || echo "")

        if [ -n "$container_id" ] && docker ps -q -f id="$container_id" | grep -q .; then
            log OK "Optional service running: $service (${container_id:0:12})"
        else
            log WARN "Optional service not running: $service"
        fi
    done

    echo ""

    if [ "$all_running" = false ]; then
        log ERROR "Some critical services failed to start"
        return 1
    fi

    # Store daemon container ID for later use
    local daemon_container_id
    daemon_container_id=$(docker compose ps -q "$DOCKER_SERVICE_NAME")
    DAEMON_PID="docker:$daemon_container_id"

    log DEBUG "Daemon container ID: $daemon_container_id"

    if [ "$DOCKER_START_ALL" = true ]; then
        log OK "All services started successfully"
    else
        log OK "Docker container started"
    fi

    return 0
}

start_systemd() {
    log INFO "Starting StorageSage daemon (systemd mode)..."
    log INFO "=========================================="

    log INFO "Running: systemctl start $SERVICE_NAME"
    echo ""

    if ! sudo systemctl start "$SERVICE_NAME" 2>&1 | tee -a "$STARTUP_LOG"; then
        log ERROR "systemctl start failed"
        echo ""
        log INFO "Checking service status..."
        sudo systemctl status "$SERVICE_NAME" --no-pager -l 2>&1 | sed 's/^/  /'
        echo ""
        log INFO "Recent journal logs:"
        sudo journalctl -u "$SERVICE_NAME" -n 20 --no-pager 2>&1 | sed 's/^/  /'
        return 1
    fi

    echo ""
    log OK "Systemd service started"

    # Get PID from systemd
    DAEMON_PID=$(systemctl show -p MainPID --value "$SERVICE_NAME")
    log DEBUG "Service PID: $DAEMON_PID"

    return 0
}

# ============================================================================
# HEALTH CHECKS
# ============================================================================

wait_for_metrics_endpoint() {
    log INFO "Waiting for metrics endpoint (max ${MAX_STARTUP_WAIT}s)..."

    local elapsed=0
    while [ $elapsed -lt $MAX_STARTUP_WAIT ]; do
        if curl -sf "$METRICS_ENDPOINT" > /dev/null 2>&1; then
            log OK "Metrics endpoint responding: $METRICS_ENDPOINT"
            return 0
        fi

        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))

        if [ $((elapsed % 10)) -eq 0 ]; then
            log DEBUG "Still waiting... (${elapsed}s)"
        fi
    done

    diagnose_error "Health check failed" "Metrics endpoint not responding after ${MAX_STARTUP_WAIT}s"
    return 1
}

wait_for_backend_health() {
    log INFO "Waiting for backend API (max ${MAX_STARTUP_WAIT}s)..."

    local elapsed=0
    while [ $elapsed -lt $MAX_STARTUP_WAIT ]; do
        # Use -k to accept self-signed certs, -s for silent, -f to fail on HTTP errors
        if curl -skf "$BACKEND_HEALTH_ENDPOINT" > /dev/null 2>&1; then
            log OK "Backend API responding: $BACKEND_HEALTH_ENDPOINT"
            return 0
        fi

        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))

        if [ $((elapsed % 10)) -eq 0 ]; then
            log DEBUG "Still waiting for backend... (${elapsed}s)"
        fi
    done

    log WARN "Backend health endpoint not responding after ${MAX_STARTUP_WAIT}s"
    log INFO "Backend may still be initializing, check logs with: docker compose logs storage-sage-backend"
    return 1
}

check_observability_endpoints() {
    log INFO "Checking observability endpoints..."

    # Check Loki
    if docker compose ps -q loki &> /dev/null; then
        local loki_url="http://localhost:3100/ready"
        if curl -sf "$loki_url" > /dev/null 2>&1; then
            log OK "Loki responding: $loki_url"
        else
            log WARN "Loki not responding: $loki_url"
        fi
    fi

    # Check Promtail
    if docker compose ps -q promtail &> /dev/null; then
        local promtail_url="http://localhost:9080/ready"
        if curl -sf "$promtail_url" > /dev/null 2>&1; then
            log OK "Promtail responding: $promtail_url"
        else
            log WARN "Promtail not responding: $promtail_url"
        fi
    fi

    return 0
}

check_daemon_running() {
    log INFO "Verifying daemon process..."

    case "$MODE" in
        direct)
            if [ -n "$DAEMON_PID" ] && ps -p "$DAEMON_PID" &> /dev/null; then
                log OK "Daemon process running: PID $DAEMON_PID"
                return 0
            else
                log ERROR "Daemon process not running"
                return 1
            fi
            ;;
        docker)
            local container_id="${DAEMON_PID#docker:}"
            if docker ps -q -f id="$container_id" | grep -q .; then
                log OK "Docker container running: $container_id"
                return 0
            else
                log ERROR "Docker container not running"
                return 1
            fi
            ;;
        systemd)
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                log OK "Systemd service active: $SERVICE_NAME"
                return 0
            else
                log ERROR "Systemd service not active"
                return 1
            fi
            ;;
    esac
}

check_log_file() {
    log INFO "Checking log file..."

    local log_file="${LOG_DIR}/cleanup.log"

    if [ ! -f "$log_file" ]; then
        log WARN "Log file not yet created: $log_file"
        return 0
    fi

    # Check if file is being written to (modified in last 10 seconds)
    if [ -f "$log_file" ]; then
        local age
        age=$(( $(date +%s) - $(stat -c %Y "$log_file" 2>/dev/null || echo 0) ))
        if [ "$age" -lt 10 ]; then
            log OK "Log file being written: $log_file"
        else
            log WARN "Log file not recently updated (${age}s old)"
        fi
    fi

    return 0
}

run_health_checks() {
    log INFO "Running runtime diagnostics..."
    echo ""

    wait_for_metrics_endpoint || return 1
    check_daemon_running || return 1
    check_log_file || return 1

    # Additional health checks for all-services mode
    if [ "$DOCKER_START_ALL" = true ] && [ "$MODE" = "docker" ]; then
        echo ""
        wait_for_backend_health || log WARN "Backend health check failed, but continuing..."
        check_observability_endpoints
    fi

    echo ""
    return 0
}

# ============================================================================
# STARTUP SUMMARY
# ============================================================================

show_startup_summary() {
    echo ""
    if [ "$DOCKER_START_ALL" = true ]; then
        log SUCCESS "All StorageSage services started successfully!"
    else
        log SUCCESS "StorageSage started successfully!"
    fi
    echo -e "${GREEN}========================================${NC}"

    case "$MODE" in
        direct)
            echo "  Mode: Direct (binary execution)"
            echo "  PID: $DAEMON_PID"
            echo "  PID File: $PID_FILE"
            ;;
        docker)
            if [ "$DOCKER_START_ALL" = true ]; then
                echo "  Mode: Docker Compose (All Services)"
                echo ""
                echo "  Services:"
                # Show daemon
                local daemon_id
                daemon_id=$(docker compose ps -q storage-sage-daemon 2>/dev/null || echo "")
                if [ -n "$daemon_id" ]; then
                    echo "    ✓ storage-sage-daemon (${daemon_id:0:12})"
                fi
                # Show backend
                local backend_id
                backend_id=$(docker compose ps -q storage-sage-backend 2>/dev/null || echo "")
                if [ -n "$backend_id" ]; then
                    echo "    ✓ storage-sage-backend (${backend_id:0:12})"
                fi
                # Show loki if running
                local loki_id
                loki_id=$(docker compose ps -q loki 2>/dev/null || echo "")
                if [ -n "$loki_id" ] && docker ps -q -f id="$loki_id" | grep -q .; then
                    echo "    ✓ loki (${loki_id:0:12})"
                fi
                # Show promtail if running
                local promtail_id
                promtail_id=$(docker compose ps -q promtail 2>/dev/null || echo "")
                if [ -n "$promtail_id" ] && docker ps -q -f id="$promtail_id" | grep -q .; then
                    echo "    ✓ promtail (${promtail_id:0:12})"
                fi
                echo ""
                echo "  Access Points:"
                echo "    Frontend/UI:  $BACKEND_URL"
                echo "    Backend API:  ${BACKEND_URL}/api/v1"
                echo "    Daemon Metrics: $METRICS_ENDPOINT"
                if [ -n "$loki_id" ]; then
                    echo "    Loki:         http://localhost:3100"
                fi
            else
                local container_id="${DAEMON_PID#docker:}"
                echo "  Mode: Docker Compose (Daemon Only)"
                echo "  Container: $DOCKER_SERVICE_NAME"
                echo "  Container ID: ${container_id:0:12}"
            fi
            ;;
        systemd)
            echo "  Mode: Systemd service"
            echo "  Service: $SERVICE_NAME"
            echo "  PID: $DAEMON_PID"
            ;;
    esac

    if [ "$DOCKER_START_ALL" = false ] || [ "$MODE" != "docker" ]; then
        echo "  Config: $CONFIG_PATH"
        echo "  Log: ${LOG_DIR}/cleanup.log"
        echo "  Metrics: $METRICS_ENDPOINT"
        echo "  Database: ${DB_DIR}/deletions.db"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}Mode: DRY-RUN (no deletions)${NC}"
    fi

    echo -e "${GREEN}========================================${NC}"
    echo ""

    log INFO "Useful commands:"
    if [ "$DOCKER_START_ALL" = true ] && [ "$MODE" = "docker" ]; then
        echo "  Open UI:      Open browser to $BACKEND_URL"
        echo "  View all logs: docker compose logs -f"
        echo "  View backend:  docker compose logs -f storage-sage-backend"
        echo "  View daemon:   docker compose logs -f storage-sage-daemon"
        echo "  Stop all:     docker compose down"
        echo "  Check status: docker compose ps"
    else
        echo "  View logs:    tail -f ${LOG_DIR}/cleanup.log"
        echo "  Check status: ${SCRIPT_DIR}/status.sh"
        echo "  Stop daemon:  ${SCRIPT_DIR}/stop.sh"
        echo "  View metrics: curl $METRICS_ENDPOINT"
    fi

    case "$MODE" in
        docker)
            if [ "$DOCKER_START_ALL" = false ]; then
                echo "  Container logs: docker compose logs -f $DOCKER_SERVICE_NAME"
            fi
            ;;
        systemd)
            echo "  Service status: systemctl status $SERVICE_NAME"
            echo "  Service logs: journalctl -u $SERVICE_NAME -f"
            ;;
    esac

    echo ""
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
            -c|--config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            -m|--mode)
                MODE="$2"
                if [[ ! "$MODE" =~ ^(auto|direct|docker|systemd)$ ]]; then
                    log ERROR "Invalid mode: $MODE"
                    log INFO "Valid modes: auto, direct, docker, systemd"
                    exit 1
                fi
                shift 2
                ;;
            -f|--foreground)
                FOREGROUND=true
                shift
                ;;
            -b|--background)
                BACKGROUND=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --once)
                RUN_ONCE=true
                shift
                ;;
            --all|--start-all)
                DOCKER_START_ALL=true
                shift
                ;;
            --check-only)
                CHECK_ONLY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --validate-config)
                check_config
                exit $?
                ;;
            --restart)
                log INFO "Restarting StorageSage..."
                if [ -x "${SCRIPT_DIR}/stop.sh" ]; then
                    "${SCRIPT_DIR}/stop.sh"
                    sleep 2
                else
                    log WARN "stop.sh not found, attempting to stop manually..."
                    if [ -f "$PID_FILE" ]; then
                        kill "$(cat "$PID_FILE")" 2>/dev/null || true
                        rm -f "$PID_FILE"
                    fi
                fi
                # Remove --restart from args and continue
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    show_banner

    parse_arguments "$@"

    # Auto-detect mode if needed
    if [ "$MODE" = "auto" ]; then
        detect_mode || exit 1
    fi

    log INFO "Startup mode: $MODE"
    log INFO "Config: ${CONFIG_PATH:-auto-detect}"
    echo ""

    # Run pre-flight checks
    run_preflight_checks || exit 1

    # Check-only mode
    if [ "$CHECK_ONLY" = true ]; then
        log SUCCESS "Diagnostics completed successfully"
        exit 0
    fi

    # Start daemon based on mode
    case "$MODE" in
        direct)
            start_direct || exit 1
            ;;
        docker)
            start_docker || exit 1
            ;;
        systemd)
            start_systemd || exit 1
            ;;
        *)
            log ERROR "Unknown mode: $MODE"
            exit 1
            ;;
    esac

    # Skip health checks in foreground mode (we exec'd)
    if [ "$FOREGROUND" = false ]; then
        run_health_checks || exit 1
        show_startup_summary
    fi

    exit 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Initialize startup log
echo "=== StorageSage Startup Log ===" > "$STARTUP_LOG"
echo "Timestamp: $(date)" >> "$STARTUP_LOG"
echo "" >> "$STARTUP_LOG"

# Run main function
main "$@"
