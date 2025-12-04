#!/bin/bash
set -euo pipefail

# ============================================================================
# StorageSage Observability Stack Verification Script
# ============================================================================
# Comprehensive health checks for all observability components
# Validates metrics flow, log ingestion, and dashboard availability
# ============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# ============================================================================
# Test Functions
# ============================================================================

test_pass() {
    echo -e "${GREEN}✅ PASS${NC} - $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

test_fail() {
    echo -e "${RED}❌ FAIL${NC} - $1"
    if [ -n "${2:-}" ]; then
        echo -e "        ${RED}↳${NC} $2"
    fi
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

test_warn() {
    echo -e "${YELLOW}⚠  WARN${NC} - $1"
    if [ -n "${2:-}" ]; then
        echo -e "        ${YELLOW}↳${NC} $2"
    fi
    ((WARNING_TESTS++))
    ((TOTAL_TESTS++))
}

test_info() {
    echo -e "${BLUE}ℹ  INFO${NC} - $1"
}

section_header() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

# ============================================================================
# Container Health Tests
# ============================================================================

test_container_health() {
    section_header "Container Health Checks"

    local CONTAINERS=(
        "storagesage-prometheus:Prometheus"
        "storagesage-loki:Loki"
        "storagesage-promtail:Promtail"
        "storagesage-grafana:Grafana"
        "storagesage-node-exporter:Node Exporter"
    )

    for container_info in "${CONTAINERS[@]}"; do
        IFS=':' read -r container_name display_name <<< "$container_info"

        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            # Check if container is running
            local status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")

            if [ "$status" = "running" ]; then
                # Check health status if healthcheck is defined
                local health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

                if [ "$health" = "healthy" ]; then
                    test_pass "$display_name container is running and healthy"
                elif [ "$health" = "none" ]; then
                    test_pass "$display_name container is running (no healthcheck)"
                else
                    test_warn "$display_name container health: $health"
                fi
            else
                test_fail "$display_name container is not running" "Status: $status"
            fi
        else
            test_fail "$display_name container not found" "Run: docker-compose -f docker-compose.observability.yml up -d"
        fi
    done
}

# ============================================================================
# Service Endpoint Tests
# ============================================================================

test_service_endpoints() {
    section_header "Service Endpoint Checks"

    # Prometheus
    if curl -f -s http://localhost:9091/-/healthy &> /dev/null; then
        test_pass "Prometheus health endpoint responding"

        # Check if Prometheus is scraping targets
        local targets_up=$(curl -s http://localhost:9091/api/v1/targets | grep -o '"health":"up"' | wc -l)
        if [ "$targets_up" -gt 0 ]; then
            test_pass "Prometheus scraping targets (${targets_up} targets up)"
        else
            test_warn "Prometheus has no targets up" "Check target configuration"
        fi
    else
        test_fail "Prometheus health endpoint not responding" "URL: http://localhost:9091"
    fi

    # Loki
    if curl -f -s http://localhost:3100/ready &> /dev/null; then
        test_pass "Loki ready endpoint responding"

        # Check if Loki has labels (indicates log ingestion)
        local labels_response=$(curl -s http://localhost:3100/loki/api/v1/label)
        if echo "$labels_response" | grep -q '"status":"success"'; then
            test_pass "Loki API responding with labels"
        else
            test_warn "Loki API not returning labels yet" "May need time to ingest logs"
        fi
    else
        test_fail "Loki ready endpoint not responding" "URL: http://localhost:3100"
    fi

    # Promtail
    if curl -f -s http://localhost:9080/ready &> /dev/null; then
        test_pass "Promtail ready endpoint responding"

        # Check Promtail metrics
        if curl -s http://localhost:9080/metrics | grep -q 'promtail_'; then
            test_pass "Promtail exporting metrics"
        else
            test_warn "Promtail metrics not found"
        fi
    else
        test_fail "Promtail ready endpoint not responding" "URL: http://localhost:9080"
    fi

    # Grafana
    if curl -f -s http://localhost:3001/api/health &> /dev/null; then
        test_pass "Grafana health endpoint responding"

        # Check Grafana datasources
        local datasources=$(curl -s http://localhost:3001/api/datasources 2>/dev/null | grep -o '"type":"prometheus"\|"type":"loki"' | wc -l)
        if [ "$datasources" -ge 2 ]; then
            test_pass "Grafana datasources configured (${datasources} datasources)"
        else
            test_warn "Grafana datasources may not be provisioned" "Found: ${datasources}, Expected: 2+"
        fi
    else
        test_fail "Grafana health endpoint not responding" "URL: http://localhost:3001"
    fi

    # Node Exporter
    if curl -f -s http://localhost:9100/metrics &> /dev/null; then
        test_pass "Node Exporter metrics endpoint responding"

        # Verify it's exporting node metrics
        if curl -s http://localhost:9100/metrics | grep -q 'node_cpu_seconds_total'; then
            test_pass "Node Exporter exporting system metrics"
        else
            test_warn "Node Exporter metrics incomplete"
        fi
    else
        test_fail "Node Exporter not responding" "URL: http://localhost:9100"
    fi
}

# ============================================================================
# Metrics Flow Tests
# ============================================================================

test_metrics_flow() {
    section_header "Metrics Flow Validation"

    # Check if StorageSage metrics are being scraped
    local storagesage_metrics=$(curl -s http://localhost:9091/api/v1/label/__name__/values | grep -o 'storagesage_' | wc -l)

    if [ "$storagesage_metrics" -gt 0 ]; then
        test_pass "StorageSage metrics flowing to Prometheus (${storagesage_metrics} metric families)"
    else
        test_warn "No StorageSage metrics found in Prometheus" "Daemon may not be running or metrics endpoint unreachable"
    fi

    # Check specific key metrics
    local KEY_METRICS=(
        "storagesage_files_deleted_total"
        "storagesage_bytes_freed_total"
        "storage_sage_free_space_percent"
        "storagesage_daemon_healthy"
    )

    for metric in "${KEY_METRICS[@]}"; do
        if curl -s http://localhost:9091/api/v1/query?query="$metric" | grep -q '"result":\['; then
            test_pass "Metric available: $metric"
        else
            test_warn "Metric not found: $metric" "May appear after first cleanup cycle"
        fi
    done

    # Check if go/process metrics are available (indicates daemon is instrumented)
    if curl -s http://localhost:9091/api/v1/label/__name__/values | grep -q 'go_goroutines'; then
        test_pass "Go runtime metrics available"
    else
        test_warn "Go runtime metrics not found"
    fi
}

# ============================================================================
# Log Flow Tests
# ============================================================================

test_log_flow() {
    section_header "Log Flow Validation"

    # Check if Loki has the storage-sage job label
    if curl -s 'http://localhost:3100/loki/api/v1/label/job/values' | grep -q 'storage-sage'; then
        test_pass "StorageSage logs flowing to Loki (job label found)"
    else
        test_warn "StorageSage job label not found in Loki" "Logs may not be ingested yet"
    fi

    # Query for recent StorageSage logs
    local now=$(date +%s)000000000  # nanoseconds
    local one_hour_ago=$(( $(date +%s) - 3600 ))000000000

    local log_count=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
        --data-urlencode 'query={job="storage-sage"}' \
        --data-urlencode "start=$one_hour_ago" \
        --data-urlencode "end=$now" \
        --data-urlencode "limit=1" | grep -o '"values":\[\[' | wc -l)

    if [ "$log_count" -gt 0 ]; then
        test_pass "StorageSage logs queryable in Loki"
    else
        test_warn "No StorageSage logs in Loki yet" "May need time for first ingestion"
    fi

    # Check if observability stack logs are being collected
    if curl -s 'http://localhost:3100/loki/api/v1/label/job/values' | grep -q 'observability'; then
        test_pass "Observability stack logs flowing to Loki"
    else
        test_info "Observability stack logs not detected (optional)"
    fi
}

# ============================================================================
# Dashboard Tests
# ============================================================================

test_grafana_dashboards() {
    section_header "Grafana Dashboard Checks"

    # Check if dashboards are provisioned
    local dashboards=$(curl -s http://localhost:3001/api/search?type=dash-db 2>/dev/null | grep -o '"title":"' | wc -l)

    if [ "$dashboards" -gt 0 ]; then
        test_pass "Grafana dashboards provisioned (${dashboards} dashboards)"
    else
        test_warn "No Grafana dashboards found" "Check dashboard provisioning config"
    fi

    # Check for StorageSage dashboard specifically
    if curl -s http://localhost:3001/api/search?query=StorageSage 2>/dev/null | grep -q 'storagesage'; then
        test_pass "StorageSage dashboard available"
    else
        test_warn "StorageSage dashboard not found" "May need manual import"
    fi
}

# ============================================================================
# Resource Usage Tests
# ============================================================================

test_resource_usage() {
    section_header "Resource Usage Checks"

    # Check container CPU usage
    local high_cpu_containers=$(docker stats --no-stream --format "{{.Name}},{{.CPUPerc}}" | grep storagesage | awk -F',' '$2 > 50.0' | cut -d',' -f1)

    if [ -z "$high_cpu_containers" ]; then
        test_pass "All containers CPU usage < 50%"
    else
        test_warn "High CPU usage detected" "Containers: $high_cpu_containers"
    fi

    # Check container memory usage
    local high_mem_containers=$(docker stats --no-stream --format "{{.Name}},{{.MemUsage}}" | grep storagesage | awk -F'[, ]' '{if (substr($2, length($2)) == "G" && substr($2, 1, length($2)-1) > 1) print $1}')

    if [ -z "$high_mem_containers" ]; then
        test_pass "All containers memory usage reasonable"
    else
        test_warn "High memory usage detected" "Containers: $high_mem_containers"
    fi

    # Check disk space
    local available_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')

    if [ "$available_space" -gt 5 ]; then
        test_pass "Sufficient disk space (${available_space}GB available)"
    else
        test_warn "Low disk space" "${available_space}GB available (recommend 5GB+)"
    fi
}

# ============================================================================
# Network Tests
# ============================================================================

test_networking() {
    section_header "Network Connectivity Checks"

    # Check if storagesage-network exists
    if docker network inspect storagesage-network &> /dev/null; then
        test_pass "storagesage-network exists"

        # Check if containers are connected
        local connected_containers=$(docker network inspect storagesage-network --format '{{range .Containers}}{{.Name}} {{end}}' | wc -w)
        test_info "Containers connected to storagesage-network: $connected_containers"
    else
        test_warn "storagesage-network not found" "May affect service discovery"
    fi

    # Check if observability network exists
    if docker network inspect storagesage-observability &> /dev/null; then
        test_pass "storagesage-observability network exists"
    else
        test_fail "storagesage-observability network not found" "Run docker-compose up first"
    fi
}

# ============================================================================
# Configuration Tests
# ============================================================================

test_configuration() {
    section_header "Configuration Validation"

    local CONFIG_FILES=(
        "config/prometheus/prometheus.yml:Prometheus config"
        "config/prometheus/alerts.yml:Prometheus alerts"
        "config/loki/loki-config.yml:Loki config"
        "config/promtail/promtail-config.yml:Promtail config"
        "config/grafana/datasources/datasources.yml:Grafana datasources"
        "config/grafana/dashboards/dashboards.yml:Grafana dashboards"
    )

    for config_info in "${CONFIG_FILES[@]}"; do
        IFS=':' read -r file_path display_name <<< "$config_info"

        if [ -f "$file_path" ]; then
            test_pass "$display_name exists"
        else
            test_fail "$display_name not found" "Path: $file_path"
        fi
    done
}

# ============================================================================
# Summary Report
# ============================================================================

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Verification Summary"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Total Tests:   $TOTAL_TESTS"
    echo -e "  ${GREEN}Passed:${NC}        $PASSED_TESTS"
    echo -e "  ${YELLOW}Warnings:${NC}      $WARNING_TESTS"
    echo -e "  ${RED}Failed:${NC}        $FAILED_TESTS"
    echo ""

    if [ $FAILED_TESTS -eq 0 ] && [ $WARNING_TESTS -eq 0 ]; then
        echo -e "${GREEN}✅ ALL CHECKS PASSED - Observability stack is healthy!${NC}"
        echo ""
        return 0
    elif [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${YELLOW}⚠  CHECKS PASSED WITH WARNINGS - Stack is operational${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}❌ SOME CHECKS FAILED - Review errors above${NC}"
        echo ""
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo "🔍 StorageSage Observability Stack Verification"
    echo "   Running comprehensive health checks..."
    echo ""

    test_container_health
    test_service_endpoints
    test_metrics_flow
    test_log_flow
    test_grafana_dashboards
    test_resource_usage
    test_networking
    test_configuration

    print_summary
}

# Run main and exit with appropriate code
main
exit $?
