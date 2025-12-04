# Service Health Monitoring

## Overview

StorageSage implements production-grade service health monitoring following patterns from `prometheus-community/systemd_exporter`. This document describes the embedded health metrics, optional systemd_exporter integration, and operational best practices.

## Architecture

### Embedded Health Metrics (Default)

StorageSage includes built-in service health monitoring that:
- Tracks daemon health status
- Monitors component health (database, config, metrics server)
- Records restart events and uptime
- Exposes health checks via `/health` endpoint
- Provides Prometheus metrics for alerting

**No external dependencies required** - all functionality is self-contained.

### Optional: systemd_exporter Integration

For comprehensive systemd ecosystem monitoring, you can deploy `systemd_exporter` alongside StorageSage to gain:
- Multi-service systemd unit monitoring
- Systemd slice and scope tracking
- Resource usage by systemd units
- Broader infrastructure visibility

## Embedded Health Metrics

### Core Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `storagesage_daemon_healthy` | Gauge | `component` | Overall daemon health (1=healthy, 0=unhealthy) |
| `storagesage_daemon_start_timestamp_seconds` | Gauge | - | Unix timestamp when daemon started |
| `storagesage_daemon_restarts_total` | Counter | `reason` | Total number of daemon restarts |
| `storagesage_component_healthy` | Gauge | `component`, `check_type` | Individual component health status |
| `storagesage_last_health_check_timestamp_seconds` | Gauge | `component` | Last successful health check timestamp |
| `storagesage_health_check_duration_seconds` | Histogram | `component` | Health check execution time |
| `storagesage_health_check_failures_consecutive` | Gauge | `component` | Consecutive health check failures |
| `storagesage_systemd_unit_state` | Gauge | `unit`, `state` | Systemd unit state (1=active, 0=inactive, -1=failed) |

### Health Check Components

The daemon automatically monitors:

1. **metrics_server** - Verifies Prometheus metrics endpoint is operational
2. **database** - Validates database connectivity (if enabled)
3. **config** - Ensures configuration is valid and loaded

Health checks run every **30 seconds** with configurable timeouts.

### HTTP Endpoints

#### `/health`

Health check endpoint with status codes:
- `200 OK` - All components healthy
- `503 Service Unavailable` - One or more components unhealthy

**Response (Healthy):**
```json
{
  "status": "ok",
  "healthy": true
}
```

**Response (Degraded):**
```json
{
  "status": "degraded",
  "healthy": false
}
```

#### `/metrics`

Prometheus-compatible metrics endpoint exposing all health metrics.

**Example metrics output:**
```
# HELP storagesage_daemon_healthy Daemon health status (1=healthy, 0=unhealthy).
# TYPE storagesage_daemon_healthy gauge
storagesage_daemon_healthy{component="overall"} 1

# HELP storagesage_daemon_start_timestamp_seconds Unix timestamp when daemon started.
# TYPE storagesage_daemon_start_timestamp_seconds gauge
storagesage_daemon_start_timestamp_seconds 1732368000

# HELP storagesage_component_healthy Individual component health status (1=healthy, 0=unhealthy).
# TYPE storagesage_component_healthy gauge
storagesage_component_healthy{component="database",check_type="functional"} 1
storagesage_component_healthy{component="config",check_type="functional"} 1
storagesage_component_healthy{component="metrics_server",check_type="functional"} 1

# HELP storagesage_daemon_restarts_total Total number of daemon restarts detected.
# TYPE storagesage_daemon_restarts_total counter
storagesage_daemon_restarts_total{reason="systemd"} 2
```

## Prometheus Alerting Rules

### Installation

Copy alerting rules to Prometheus configuration:

```bash
sudo cp deploy/prometheus/storagesage_alerts.yml /etc/prometheus/alerts/

# Add to prometheus.yml:
rule_files:
  - "/etc/prometheus/alerts/storagesage_alerts.yml"

# Reload Prometheus
sudo systemctl reload prometheus
```

### Alert Rules

#### Critical Alerts

| Alert | Condition | Duration | Description |
|-------|-----------|----------|-------------|
| `StorageSageDaemonDown` | `storagesage_daemon_healthy == 0` | 5 minutes | Daemon health check failing |
| `StorageSageMetricsMissing` | `absent(storagesage_daemon_healthy)` | 5 minutes | No metrics received (service down) |
| `StorageSageSystemdUnitFailed` | `storagesage_systemd_unit_state{state="failed"} == -1` | 1 minute | Systemd unit in failed state |
| `StorageSageCleanupErrors` | `rate(storagesage_errors_total[5m]) > 0.1` | 5 minutes | High error rate during cleanup |

#### Warning Alerts

| Alert | Condition | Duration | Description |
|-------|-----------|----------|-------------|
| `StorageSageComponentUnhealthy` | `storagesage_component_healthy == 0` | 2 minutes | Component health check failing |
| `StorageSageFrequentRestarts` | `rate(storagesage_daemon_restarts_total[1h]) > 3` | 5 minutes | Restarting more than 3x per hour |
| `StorageSageHealthCheckFailures` | `storagesage_health_check_failures_consecutive > 5` | 1 minute | 5+ consecutive failures |
| `StorageSageNoRecentCleanup` | `(time() - storagesage_cleanup_last_run_timestamp_seconds) > 7200` | 10 minutes | No cleanup in 2+ hours |

## Grafana Dashboard

### Installation

Import the service health dashboard:

```bash
# Using Grafana API
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -d @deploy/grafana/service_health_dashboard.json

# Or import via UI
# Dashboards -> Import -> Upload JSON file
# Select: deploy/grafana/service_health_dashboard.json
```

### Dashboard Panels

The dashboard includes:

1. **Overall Service Health** - Real-time health status (green/red)
2. **Service Uptime** - Daemon uptime since last start
3. **Total Restarts** - Cumulative restart counter
4. **Component Health Status** - Per-component health matrix
5. **Health Check Failures** - Consecutive failure tracking
6. **Health Check Duration** - p50/p95 latency metrics
7. **Restart History** - Timeline of restart events
8. **Systemd Unit State** - Current systemd status
9. **Error Rate** - Errors per second trend
10. **Last Health Check Timestamps** - Table view of last checks

## Optional: systemd_exporter Integration

### Why Use systemd_exporter?

Deploy `systemd_exporter` if you need:
- Monitoring of multiple systemd services beyond StorageSage
- Systemd slice/scope resource tracking
- Per-unit CPU/memory/IO metrics
- System-wide service dependency mapping

### Installation

```bash
# Install systemd_exporter
sudo dnf install -y golang
git clone https://github.com/prometheus-community/systemd_exporter.git
cd systemd_exporter
make build
sudo cp systemd_exporter /usr/local/bin/

# Create systemd service
sudo tee /etc/systemd/system/systemd_exporter.service <<EOF
[Unit]
Description=Systemd Exporter
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/usr/local/bin/systemd_exporter \\
  --systemd.collector.enable-restart-count \\
  --systemd.collector.unit-include="storage-sage.service" \\
  --web.listen-address=:9558

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now systemd_exporter
```

### Prometheus Configuration

Add systemd_exporter scrape target:

```yaml
scrape_configs:
  - job_name: 'systemd'
    static_configs:
      - targets: ['localhost:9558']

  - job_name: 'storagesage'
    static_configs:
      - targets: ['localhost:9090']  # Default StorageSage metrics port
```

### Available systemd_exporter Metrics

```
# Systemd unit state
systemd_unit_state{name="storage-sage.service",state="active"} 1

# Unit restart count
systemd_unit_start_time_seconds{name="storage-sage.service"} 1732368000

# Resource usage
systemd_unit_tasks_current{name="storage-sage.service"} 5
```

### Combined Alerting

Create alerts combining both metric sources:

```yaml
- alert: StorageSageSystemdResourceLimit
  expr: |
    systemd_unit_tasks_current{name="storage-sage.service"} > 90
    or
    systemd_unit_memory_current_bytes{name="storage-sage.service"} > 500000000
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "StorageSage approaching systemd resource limits"
```

## Operational Procedures

### Health Check Verification

```bash
# Check overall health
curl -s http://localhost:9090/health | jq .

# Query specific component health
curl -s http://localhost:9090/metrics | grep storagesage_component_healthy

# Check for recent restarts
curl -s http://localhost:9090/metrics | grep storagesage_daemon_restarts_total
```

### Monitoring Service Restarts

```bash
# View restart counter
curl -s http://localhost:9090/metrics | grep storagesage_daemon_restarts_total

# Check systemd restart reasons
sudo journalctl -u storage-sage.service | grep -i restart

# View systemd unit state
systemctl status storage-sage.service
```

### Health Check Tuning

Adjust health check interval in code ([cmd/storage-sage/main.go](../cmd/storage-sage/main.go)):

```go
// Default: 30 second interval
healthChecker := metrics.NewHealthChecker(30 * time.Second)

// More aggressive: 10 second interval
healthChecker := metrics.NewHealthChecker(10 * time.Second)
```

### Debugging Unhealthy Components

```bash
# View component failure details
curl -s http://localhost:9090/metrics | grep storagesage_health_check_failures_consecutive

# Check health check duration (slow checks)
curl -s http://localhost:9090/metrics | grep storagesage_health_check_duration_seconds

# Inspect daemon logs for health check errors
sudo journalctl -u storage-sage.service -f | grep -i health
```

## Systemd Service Configuration

The systemd unit file ([storage-sage.service](../storage-sage.service)) is configured for:

- **Restart Policy**: `Restart=on-failure` with `RestartSec=10`
- **Timeout**: `TimeoutStopSec=30` for graceful shutdown
- **Resource Limits**: `CPUQuota=10%`, `MemoryMax=512M`
- **Logging**: Outputs to systemd journal via `StandardOutput=journal`

### Monitoring Systemd Restart Events

StorageSage detects systemd restarts via the `SYSTEMD_EXEC_PID` environment variable and increments `storagesage_daemon_restarts_total{reason="systemd"}`.

```bash
# View restart history in metrics
curl -s http://localhost:9090/metrics | grep 'storagesage_daemon_restarts_total{reason="systemd"}'

# Query restart rate in Prometheus
rate(storagesage_daemon_restarts_total{reason="systemd"}[1h])
```

## Integration with Existing Monitoring

### Alertmanager Integration

Configure Alertmanager to route StorageSage alerts:

```yaml
route:
  receiver: 'default'
  routes:
    - match:
        component: 'daemon'
        severity: 'critical'
      receiver: 'pagerduty'
    - match:
        component: 'cleanup'
        severity: 'warning'
      receiver: 'slack'

receivers:
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<key>'
  - name: 'slack'
    slack_configs:
      - api_url: '<webhook>'
        channel: '#storage-alerts'
```

### Loki Log Integration

Query service health events from logs:

```logql
{job="storagesage"} |= "Health monitoring" or "health check" or "restart"
```

## Testing Health Monitoring

### Simulate Component Failure

```bash
# Trigger database failure (if using database)
sudo chmod 000 /var/lib/storage-sage/deletions.db

# Wait 30 seconds for next health check
sleep 30

# Verify unhealthy state
curl -s http://localhost:9090/metrics | grep 'storagesage_component_healthy{component="database"}'
# Should show: storagesage_component_healthy{component="database",check_type="functional"} 0

# Restore permissions
sudo chmod 644 /var/lib/storage-sage/deletions.db
```

### Test Restart Detection

```bash
# Restart via systemd
sudo systemctl restart storage-sage.service

# Wait for startup (10 seconds)
sleep 10

# Verify restart was recorded
curl -s http://localhost:9090/metrics | grep storagesage_daemon_restarts_total
```

### Validate Alerting Pipeline

```bash
# Send test alert
amtool alert add \
  alertname=StorageSageDaemonDown \
  component=daemon \
  severity=critical \
  --annotation="summary=Test alert for StorageSage"

# Verify alert fires in Prometheus
# Navigate to: http://localhost:9090/alerts
```

## Performance Impact

Health monitoring overhead:
- **CPU**: < 0.1% additional CPU usage
- **Memory**: ~2MB for health checker goroutines
- **Network**: ~500 bytes/second for metrics updates
- **Disk**: No additional disk I/O

Health checks execute in parallel with 5-second default timeouts, ensuring non-blocking operation.

## Troubleshooting

### Health Endpoint Returns 503

```bash
# Check which component is failing
curl -s http://localhost:9090/metrics | grep 'storagesage_component_healthy.*0'

# View consecutive failure count
curl -s http://localhost:9090/metrics | grep storagesage_health_check_failures_consecutive

# Inspect logs
sudo journalctl -u storage-sage.service -n 100 | grep -i health
```

### Metrics Not Appearing

```bash
# Verify metrics server is running
sudo netstat -tlnp | grep 9090

# Check for initialization errors
sudo journalctl -u storage-sage.service | grep -i "metrics"

# Validate Prometheus scrape config
curl -s http://localhost:9090/metrics | head -20
```

### False Positive Alerts

Adjust alert thresholds in `storagesage_alerts.yml`:

```yaml
# Increase tolerance for restart alerts
- alert: StorageSageFrequentRestarts
  expr: rate(storagesage_daemon_restarts_total[1h]) > 5  # Was: 3
  for: 10m  # Was: 5m
```

## Best Practices

1. **Set up alerting first** - Configure Prometheus alerts before deploying to production
2. **Monitor the monitors** - Use meta-alerts to detect Prometheus/Grafana failures
3. **Tune thresholds** - Adjust alert thresholds based on your operational patterns
4. **Test failure scenarios** - Regularly simulate component failures to validate alerting
5. **Review restart patterns** - Investigate any restart events, even if automated recovery worked
6. **Integrate with runbooks** - Link alerts to operational procedures for faster resolution
7. **Use health checks in CI/CD** - Gate deployments on health endpoint returning 200 OK

## References

- [Prometheus Alerting Best Practices](https://prometheus.io/docs/practices/alerting/)
- [systemd_exporter GitHub](https://github.com/prometheus-community/systemd_exporter)
- [Grafana Dashboard Design Guidelines](https://grafana.com/docs/grafana/latest/dashboards/)
- [StorageSage Metrics Documentation](./METRICS.md)
