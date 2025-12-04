#!/bin/bash
set -euo pipefail

# ============================================================================
# StorageSage Observability Stack Quickstart
# ============================================================================
# Deploys the complete monitoring stack: Prometheus + Loki + Promtail + Grafana
# One-command setup for production-grade observability
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.observability.yml"
CONFIG_DIR="${PROJECT_ROOT}/config"
USER_ID=$(id -u)

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

print_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

check_prerequisites() {
    print_header "Pre-flight Checks"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        echo "  Install from: https://docs.docker.com/get-docker/"
        exit 1
    fi
    log_success "Docker installed: $(docker --version | cut -d' ' -f3)"

    # Check Docker Compose
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
        log_success "Docker Compose V2 installed: $(docker compose version --short)"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
        log_success "Docker Compose V1 installed: $(docker-compose --version | cut -d' ' -f3)"
    else
        log_error "Docker Compose is not installed"
        echo "  Install from: https://docs.docker.com/compose/install/"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    log_success "Docker daemon is running"

    # Check for required ports
    local REQUIRED_PORTS=(3001 3100 9080 9091 9100)
    local PORTS_IN_USE=()

    for port in "${REQUIRED_PORTS[@]}"; do
        if lsof -i ":$port" &> /dev/null || netstat -tuln 2>/dev/null | grep -q ":$port "; then
            PORTS_IN_USE+=("$port")
        fi
    done

    if [ ${#PORTS_IN_USE[@]} -gt 0 ]; then
        log_warning "The following ports are already in use: ${PORTS_IN_USE[*]}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "All required ports are available"
    fi

    # Check disk space
    local AVAILABLE_SPACE=$(df -BG "$PROJECT_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 5 ]; then
        log_warning "Low disk space: ${AVAILABLE_SPACE}GB available (recommend 5GB+)"
    else
        log_success "Sufficient disk space: ${AVAILABLE_SPACE}GB available"
    fi
}

verify_config_files() {
    print_header "Configuration Verification"

    local REQUIRED_FILES=(
        "config/prometheus/prometheus.yml"
        "config/prometheus/alerts.yml"
        "config/loki/loki-config.yml"
        "config/promtail/promtail-config.yml"
        "config/grafana/datasources/datasources.yml"
        "config/grafana/dashboards/dashboards.yml"
        "docker-compose.observability.yml"
    )

    local MISSING_FILES=()

    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$file" ]; then
            MISSING_FILES+=("$file")
        fi
    done

    if [ ${#MISSING_FILES[@]} -gt 0 ]; then
        log_error "Missing configuration files:"
        for file in "${MISSING_FILES[@]}"; do
            echo "    - $file"
        done
        exit 1
    fi

    log_success "All configuration files present"
}

create_directories() {
    print_header "Directory Setup"

    # Ensure config directories exist with proper permissions
    mkdir -p "$CONFIG_DIR"/{prometheus,loki,promtail,grafana/{datasources,dashboards}}
    log_success "Configuration directories created"

    # Create data directories (Docker volumes will use these)
    mkdir -p "$PROJECT_ROOT/data"/{prometheus,loki,grafana,promtail-positions}
    log_success "Data directories created"

    # Set permissions
    if [ "$(uname)" != "Darwin" ]; then
        chown -R "$USER_ID:$USER_ID" "$CONFIG_DIR" 2>/dev/null || log_warning "Could not set ownership (may need sudo)"
    fi
}

create_network() {
    print_header "Network Setup"

    # Create storagesage-network if it doesn't exist
    if ! docker network inspect storagesage-network &> /dev/null; then
        docker network create storagesage-network
        log_success "Created storagesage-network"
    else
        log_info "Network storagesage-network already exists"
    fi
}

start_stack() {
    print_header "Starting Observability Stack"

    cd "$PROJECT_ROOT"

    log_info "Pulling latest images..."
    USER_ID=$USER_ID $DOCKER_COMPOSE -f "$COMPOSE_FILE" pull

    log_info "Starting services..."
    USER_ID=$USER_ID $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d

    log_success "All services started"
}

wait_for_health() {
    print_header "Health Checks"

    local MAX_WAIT=120
    local WAIT_INTERVAL=5

    # Prometheus
    log_info "Waiting for Prometheus..."
    local elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        if curl -f -s http://localhost:9091/-/healthy &> /dev/null; then
            log_success "Prometheus is healthy"
            break
        fi
        sleep $WAIT_INTERVAL
        elapsed=$((elapsed + WAIT_INTERVAL))
    done

    if [ $elapsed -ge $MAX_WAIT ]; then
        log_warning "Prometheus health check timeout (continuing anyway)"
    fi

    # Loki
    log_info "Waiting for Loki..."
    elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        if curl -f -s http://localhost:3100/ready &> /dev/null; then
            log_success "Loki is ready"
            break
        fi
        sleep $WAIT_INTERVAL
        elapsed=$((elapsed + WAIT_INTERVAL))
    done

    if [ $elapsed -ge $MAX_WAIT ]; then
        log_warning "Loki health check timeout (continuing anyway)"
    fi

    # Promtail
    log_info "Waiting for Promtail..."
    elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        if curl -f -s http://localhost:9080/ready &> /dev/null; then
            log_success "Promtail is ready"
            break
        fi
        sleep $WAIT_INTERVAL
        elapsed=$((elapsed + WAIT_INTERVAL))
    done

    if [ $elapsed -ge $MAX_WAIT ]; then
        log_warning "Promtail health check timeout (continuing anyway)"
    fi

    # Grafana
    log_info "Waiting for Grafana..."
    elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        if curl -f -s http://localhost:3001/api/health &> /dev/null; then
            log_success "Grafana is ready"
            break
        fi
        sleep $WAIT_INTERVAL
        elapsed=$((elapsed + WAIT_INTERVAL))
    done

    if [ $elapsed -ge $MAX_WAIT ]; then
        log_warning "Grafana health check timeout (continuing anyway)"
    fi
}

verify_metrics() {
    print_header "Metrics Verification"

    # Check if Prometheus is scraping targets
    log_info "Checking Prometheus targets..."
    if curl -s http://localhost:9091/api/v1/targets | grep -q '"health":"up"'; then
        log_success "Prometheus targets are being scraped"
    else
        log_warning "Some Prometheus targets may be down (check Prometheus UI)"
    fi

    # Check if Loki is receiving logs
    log_info "Checking Loki ingestion..."
    if curl -s 'http://localhost:3100/loki/api/v1/label' | grep -q '"status":"success"'; then
        log_success "Loki API is responding"
    else
        log_warning "Loki may not be receiving logs yet (needs time to collect)"
    fi
}

print_access_info() {
    print_header "Observability Stack Ready"

    echo ""
    echo "🎉 Deployment successful! Access your monitoring stack:"
    echo ""
    echo "  📊 Grafana:      http://localhost:3001"
    echo "                   User: admin / Pass: admin"
    echo ""
    echo "  📈 Prometheus:   http://localhost:9091"
    echo "  📝 Loki:         http://localhost:3100"
    echo "  🚚 Promtail:     http://localhost:9080"
    echo "  💻 Node Exporter: http://localhost:9100"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Quick Start Guide:"
    echo ""
    echo "  1. Open Grafana: http://localhost:3001"
    echo "  2. Login with admin/admin (change password when prompted)"
    echo "  3. Navigate to Dashboards → StorageSage → StorageSage Overview"
    echo "  4. Explore logs in Explore → Loki → {job=\"storage-sage\"}"
    echo ""
    echo "Useful Commands:"
    echo ""
    echo "  View logs:       $DOCKER_COMPOSE -f $COMPOSE_FILE logs -f"
    echo "  Stop stack:      $DOCKER_COMPOSE -f $COMPOSE_FILE down"
    echo "  Restart:         $DOCKER_COMPOSE -f $COMPOSE_FILE restart"
    echo "  Status:          $DOCKER_COMPOSE -f $COMPOSE_FILE ps"
    echo "  Verify health:   ./scripts/verify-observability.sh"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo "🚀 StorageSage Observability Stack Quickstart"
    echo "   Deploying: Prometheus + Loki + Promtail + Grafana + Node Exporter"
    echo ""

    check_prerequisites
    verify_config_files
    create_directories
    create_network
    start_stack
    wait_for_health
    verify_metrics
    print_access_info

    log_success "Quickstart complete!"
}

# Run main function
main "$@"
