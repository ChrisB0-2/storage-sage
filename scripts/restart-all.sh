#!/bin/bash
# StorageSage Unified Restart Script
# Stops and restarts all StorageSage services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

show_banner() {
    echo -e "${CYAN}"
    echo "========================================"
    echo "  StorageSage Restart"
    echo "========================================"
    echo -e "${NC}"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Restarts all StorageSage services (stop + start).

OPTIONS:
  -h, --help              Show this help message
  --no-build              Skip rebuild before starting
  --force                 Force kill processes on stop

EXAMPLES:
  # Restart all services
  $0

  # Restart without rebuilding
  $0 --no-build

  # Force restart (force kill + restart)
  $0 --force

EOF
}

main() {
    show_banner

    local stop_args=()
    local start_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --force)
                stop_args+=("--force")
                shift
                ;;
            --no-build)
                start_args+=("--no-build")
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Stop services
    log_info "Stopping services..."
    if ! "${SCRIPT_DIR}/stop-all.sh" "${stop_args[@]+"${stop_args[@]}"}"; then
        echo "Warning: Stop script reported errors, continuing..."
    fi

    echo ""
    sleep 2

    # Start services
    log_info "Starting services..."
    if ! "${SCRIPT_DIR}/start-all.sh" "${start_args[@]+"${start_args[@]}"}"; then
        echo "Error: Start script failed"
        exit 1
    fi

    echo ""
    log_success "Restart completed successfully"
}

main "$@"
