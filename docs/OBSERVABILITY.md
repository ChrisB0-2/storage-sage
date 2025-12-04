# StorageSage Observability Stack

Complete production-grade monitoring solution integrating **Prometheus**, **Loki**, **Promtail**, **Grafana**, and **Node Exporter** for comprehensive observability of the StorageSage system.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  StorageSage Observability Stack                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Application Layer (Monitored Services)                          │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐                     │
│  │ Daemon   │  │ Backend  │  │ Frontend  │                     │
│  │ :9090    │  │ :8443    │  │ :80/443   │                     │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘                     │
│       │metrics      │metrics        │logs                       │
│       │             │               │                           │
│  Collection & Aggregation Layer                                 │
│  ┌────▼───────┐  ┌─▼────────┐  ┌──▼───────┐                   │
│  │ Prometheus │  │   Loki   │  │ Promtail │                   │
│  │   :9091    │  │  :3100   │  │  :9080   │                   │
│  └─────┬──────┘  └────┬─────┘  └────┬─────┘                   │
│        │              │              │                          │
│  Visualization Layer                                            │
│  ┌─────▼──────────────▼──────────────▼─────┐                   │
│  │          Grafana (:3001)                 │                   │
│  │  • Prometheus Datasource                 │                   │
│  │  • Loki Datasource                       │                   │
│  │  • Pre-provisioned Dashboards            │                   │
│  └──────────────────────────────────────────┘                   │
│                                                                  │
│  System Metrics                                                 │
│  ┌──────────────────────┐                                       │
│  │ Node Exporter :9100  │                                       │
│  │ (CPU, Mem, Disk, I/O)│                                       │
│  └──────────────────────┘                                       │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### One-Command Deployment

```bash
# Deploy complete observability stack
./scripts/quickstart-observability.sh

# Verify all components are healthy
./scripts/verify-observability.sh
```

### Manual Deployment

```bash
# 1. Create environment configuration
cp .env.example .env
export USER_ID=$(id -u)

# 2. Start the observability stack
docker compose -f docker-compose.observability.yml up -d

# 3. Verify services are running
docker compose -f docker-compose.observability.yml ps

# 4. Check health
./scripts/verify-observability.sh
```

## Access Points

| Service | URL | Credentials | Purpose |
|---------|-----|-------------|---------|
| **Grafana** | http://localhost:3001 | admin / admin | Dashboards and visualization |
| **Prometheus** | http://localhost:9091 | None | Metrics query and alerting |
| **Loki** | http://localhost:3100 | None | Log aggregation API |
| **Promtail** | http://localhost:9080 | None | Log shipping status |
| **Node Exporter** | http://localhost:9100 | None | System metrics |

## Components

### Prometheus (Metrics)

**Port:** 9091
**Purpose:** Time-series metrics collection and storage

**Scrape Targets:**
- `storagesage-daemon:9090` - Cleanup engine metrics
- `storagesage-backend:9090` - API server metrics
- `loki:3100` - Log system metrics
- `promtail:9080` - Log shipper metrics
- `grafana:3000` - Dashboard metrics
- `localhost:9100` - System metrics (Node Exporter)

**Key Metrics Collected:**
```promql
# Cleanup metrics
storagesage_files_deleted_total
storagesage_bytes_freed_total
storage_sage_free_space_percent
storage_sage_cleanup_last_run_timestamp

# Health metrics
storagesage_daemon_healthy
storagesage_component_healthy
storagesage_health_check_duration_seconds

# Error metrics
storagesage_errors_total
storagesage_health_check_failures_consecutive
```

**Configuration:**
- File: [config/prometheus/prometheus.yml](../config/prometheus/prometheus.yml)
- Alerts: [config/prometheus/alerts.yml](../config/prometheus/alerts.yml)
- Retention: 30 days
- Scrape interval: 15 seconds

### Loki (Logs)

**Port:** 3100
**Purpose:** Log aggregation and querying

**Log Sources:**
- Docker container logs (all StorageSage services)
- System logs (`/var/log/syslog`, `/var/log/messages`)
- Application-specific logs

**Log Labels:**
```
job="storage-sage"
component="daemon|backend|frontend"
service="storage-sage-daemon|storage-sage-backend"
level="INFO|WARN|ERROR|DEBUG"
```

**Configuration:**
- File: [config/loki/loki-config.yml](../config/loki/loki-config.yml)
- Retention: 30 days
- Max query length: 30 days
- Schema: v13 (TSDB)

**Query Examples:**
```logql
# All StorageSage logs
{job="storage-sage"}

# Daemon errors only
{job="storage-sage",component="daemon"} |= "ERROR"

# Files deleted
{job="storage-sage"} |= "DELETED"

# Cleanup cycles
{job="storage-sage"} |~ "cleanup_mode=(AGE|DISK-USAGE|STACK)"
```

### Promtail (Log Shipping)

**Port:** 9080
**Purpose:** Collects and forwards logs to Loki

**Collection Methods:**
- Docker container discovery (auto-detects StorageSage containers)
- Static file paths (`/var/log/*`)
- Systemd journal integration (optional)

**Pipeline Processing:**
- JSON log parsing
- Log level extraction
- Timestamp normalization
- Label attachment

**Configuration:**
- File: [config/promtail/promtail-config.yml](../config/promtail/promtail-config.yml)
- Position tracking: `/tmp/positions/positions.yaml`
- Batch size: 1MB
- Batch wait: 1 second

### Grafana (Visualization)

**Port:** 3001
**Default Credentials:** admin / admin

**Pre-configured Datasources:**
1. **Prometheus** (default)
   - URL: `http://prometheus:9090`
   - UID: `prometheus-storagesage`
2. **Loki**
   - URL: `http://loki:3100`
   - UID: `loki-storagesage`

**Pre-built Dashboards:**
- **StorageSage Overview** - Main operational dashboard
  - Free space gauges per path
  - Files deleted rate
  - Bytes freed total
  - Daemon health status
  - Recent logs

**Configuration:**
- Datasources: [config/grafana/datasources/datasources.yml](../config/grafana/datasources/datasources.yml)
- Dashboards: [config/grafana/dashboards/](../config/grafana/dashboards/)
- Auto-provisioning enabled

### Node Exporter (System Metrics)

**Port:** 9100
**Purpose:** Host-level metrics (CPU, memory, disk, network)

**Metrics Exported:**
- CPU usage and saturation
- Memory utilization
- Disk I/O and space
- Network throughput
- File descriptor usage
- System load averages

**Configuration:**
- Network mode: `host` (for accurate system metrics)
- Read-only filesystem mounts

## Dashboard Usage

### Accessing Grafana

1. Navigate to http://localhost:3001
2. Login with `admin` / `admin`
3. Change password when prompted (production deployments)

### StorageSage Overview Dashboard

**Location:** Dashboards → StorageSage → StorageSage Overview

**Panels:**
1. **Free Space by Path** (Gauge)
   - Real-time disk space percentage
   - Color-coded thresholds (red < 10%, yellow < 20%, green > 30%)
   - One gauge per monitored path

2. **Files Deleted Rate** (Time series)
   - Files deleted per minute
   - Shows cleanup activity over time

3. **Total Files Deleted** (Stat)
   - Cumulative deletion counter
   - Updates on every cleanup cycle

4. **Total Bytes Freed** (Stat)
   - Cumulative space reclaimed
   - Human-readable byte formatting

5. **Daemon Health Status** (Stat)
   - Overall health indicator
   - Green = healthy, Red = unhealthy

6. **Last Cleanup Time** (Stat)
   - Time since last cleanup execution
   - Updates on each cycle

7. **StorageSage Logs** (Logs panel)
   - Live log stream from all components
   - Filterable by level, component, service

### Creating Custom Dashboards

**Example: Cleanup Efficiency Dashboard**

```json
{
  "panels": [
    {
      "title": "Cleanup Modes Over Time",
      "targets": [
        {
          "expr": "storage_sage_cleanup_last_mode"
        }
      ]
    },
    {
      "title": "Bytes Freed per Cleanup Cycle",
      "targets": [
        {
          "expr": "increase(storagesage_bytes_freed_total[15m])"
        }
      ]
    }
  ]
}
```

## Alerting

### Pre-configured Alerts

Located in [config/prometheus/alerts.yml](../config/prometheus/alerts.yml):

**Critical Alerts:**
- `CriticalDiskSpaceLow` - Free space < 5%
- `DaemonDown` - Daemon unreachable for 2+ minutes
- `DaemonUnhealthy` - Health check failures
- `StackModeActivated` - Emergency cleanup triggered

**Warning Alerts:**
- `LowDiskSpace` - Free space < 10%
- `NoRecentCleanup` - No cleanup in 1+ hour
- `CleanupFailureRate` - Elevated error rate
- `HighCPUUsage` - Daemon CPU > 50%

**System Alerts:**
- `HighSystemCPU` - Host CPU > 80%
- `HighSystemMemory` - Host memory > 90%
- `DiskIOSaturation` - I/O saturation detected

### Alert Integration

**Alertmanager Setup (Optional):**

```yaml
# config/alertmanager/alertmanager.yml
route:
  group_by: ['alertname', 'severity']
  receiver: 'slack-notifications'

receivers:
  - name: 'slack-notifications'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#storagesage-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

Enable in [docker-compose.observability.yml](../docker-compose.observability.yml):
```yaml
services:
  alertmanager:
    image: prom/alertmanager:v0.27.0
    ports:
      - "9093:9093"
    volumes:
      - ./config/alertmanager:/etc/alertmanager
```

## Querying

### Prometheus Queries (PromQL)

**Cleanup Performance:**
```promql
# Files deleted per minute (5min average)
rate(storagesage_files_deleted_total[5m]) * 60

# Bytes freed per hour
increase(storagesage_bytes_freed_total[1h])

# Average cleanup duration
rate(storagesage_cleanup_duration_seconds_sum[5m]) /
rate(storagesage_cleanup_duration_seconds_count[5m])
```

**Health Monitoring:**
```promql
# Daemon uptime (seconds)
time() - storagesage_daemon_start_timestamp_seconds

# Component health status
storagesage_component_healthy{component=~".*"}

# Error rate (errors per second)
rate(storagesage_errors_total[5m])
```

**Resource Usage:**
```promql
# Daemon CPU percentage
rate(process_cpu_seconds_total{job="storagesage-daemon"}[5m]) * 100

# Daemon memory usage (bytes)
process_resident_memory_bytes{job="storagesage-daemon"}

# Goroutine count
go_goroutines{job="storagesage-daemon"}
```

### Loki Queries (LogQL)

**Basic Log Queries:**
```logql
# All StorageSage logs
{job="storage-sage"}

# Daemon logs only
{job="storage-sage",component="daemon"}

# Error logs across all components
{job="storage-sage"} |= "level=ERROR"

# Logs from last hour
{job="storage-sage"} | json | __timestamp__ > now() - 1h
```

**Advanced Queries:**
```logql
# Count errors per minute
sum(rate({job="storage-sage"} |= "ERROR" [1m]))

# Extract cleanup mode distribution
sum by (mode) (
  count_over_time({job="storage-sage"} |~ "cleanup_mode=(\\w+)" [1h])
)

# Files deleted (extracted from logs)
{job="storage-sage"}
  |= "DELETED"
  | regexp "path=(?P<path>\\S+)"
  | line_format "{{.path}}"
```

## Maintenance

### Data Retention

**Prometheus:**
- Default: 30 days
- Configure: `--storage.tsdb.retention.time=30d` in compose file
- Manual cleanup: Not required (auto-purges old data)

**Loki:**
- Default: 30 days
- Configure: `retention_period: 30d` in [loki-config.yml](../config/loki/loki-config.yml)
- Compaction: Automatic every 10 minutes

### Backup & Restore

**Prometheus Data:**
```bash
# Backup
docker run --rm -v storagesage-prometheus-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/prometheus-backup.tar.gz -C /data .

# Restore
docker run --rm -v storagesage-prometheus-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/prometheus-backup.tar.gz -C /data
```

**Loki Data:**
```bash
# Backup
docker run --rm -v storagesage-loki-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/loki-backup.tar.gz -C /data .

# Restore
docker run --rm -v storagesage-loki-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/loki-backup.tar.gz -C /data
```

**Grafana Dashboards:**
```bash
# Export all dashboards
curl -s http://admin:admin@localhost:3001/api/search | jq -r '.[] | .uid' | \
  while read uid; do
    curl -s http://admin:admin@localhost:3001/api/dashboards/uid/$uid | \
      jq '.dashboard' > dashboard-$uid.json
  done
```

### Scaling & Performance

**High-Volume Deployments:**

1. **Increase Prometheus resources:**
   ```yaml
   prometheus:
     deploy:
       resources:
         limits:
           memory: 4g
           cpus: '2'
   ```

2. **Enable Loki caching:**
   ```yaml
   # config/loki/loki-config.yml
   query_range:
     results_cache:
       cache:
         embedded_cache:
           max_size_mb: 1000
   ```

3. **Optimize Promtail batch settings:**
   ```yaml
   # config/promtail/promtail-config.yml
   clients:
     - batchwait: 500ms
       batchsize: 2097152  # 2MB
   ```

### Troubleshooting

**Prometheus not scraping targets:**
```bash
# Check target status
curl http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | {job, health, lastError}'

# Verify network connectivity
docker exec storagesage-prometheus wget -O- http://storage-sage-daemon:9090/metrics
```

**Loki not receiving logs:**
```bash
# Check Promtail status
curl http://localhost:9080/metrics | grep promtail_sent_entries_total

# Check Loki ingestion
curl http://localhost:3100/metrics | grep loki_distributor_lines_received_total

# Verify log query
curl -G http://localhost:3100/loki/api/v1/query \
  --data-urlencode 'query={job="storage-sage"}' \
  --data-urlencode 'limit=10'
```

**Grafana datasources not connecting:**
```bash
# Test Prometheus datasource
curl http://localhost:3001/api/datasources/proxy/1/api/v1/query?query=up

# Test Loki datasource
curl http://localhost:3001/api/datasources/proxy/2/loki/api/v1/labels

# Check datasource health
curl http://admin:admin@localhost:3001/api/datasources | jq '.[] | {name, type, url}'
```

## Security Considerations

### Production Hardening

1. **Change default credentials:**
   ```bash
   # Update .env file
   GRAFANA_PASSWORD=$(openssl rand -base64 32)
   ```

2. **Enable TLS for Grafana:**
   ```yaml
   grafana:
     environment:
       - GF_SERVER_PROTOCOL=https
       - GF_SERVER_CERT_FILE=/etc/grafana/cert.pem
       - GF_SERVER_CERT_KEY=/etc/grafana/key.pem
   ```

3. **Restrict network access:**
   ```yaml
   prometheus:
     ports:
       - "127.0.0.1:9091:9090"  # Localhost only
   ```

4. **Enable authentication for Prometheus:**
   ```yaml
   # config/prometheus/web.yml
   basic_auth_users:
     admin: $2y$10$...  # bcrypt hash
   ```

### Access Control

**Grafana Roles:**
- Admin: Full access, can provision datasources
- Editor: Can create/edit dashboards
- Viewer: Read-only dashboard access

**Loki Multi-tenancy:**
```yaml
# config/loki/loki-config.yml
auth_enabled: true
```

## Integration with CI/CD

### Automated Deployment

```yaml
# .github/workflows/deploy-observability.yml
name: Deploy Observability Stack

on:
  push:
    branches: [main]
    paths:
      - 'config/**'
      - 'docker-compose.observability.yml'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy stack
        run: ./scripts/quickstart-observability.sh
      - name: Verify health
        run: ./scripts/verify-observability.sh
```

### Monitoring Pipeline Health

```bash
# Add to your CI/CD pipeline
./scripts/verify-observability.sh || {
  echo "Observability stack health check failed"
  docker compose -f docker-compose.observability.yml logs
  exit 1
}
```

## Cost Optimization

### Resource Limits

```yaml
# docker-compose.observability.yml
services:
  prometheus:
    deploy:
      resources:
        limits:
          memory: 2g
          cpus: '1'
        reservations:
          memory: 512m
          cpus: '0.5'
```

### Storage Management

- Use shorter retention periods for dev/test: 7 days
- Enable compression in Loki config
- Regular backup and purge of old data
- Use external object storage for long-term retention (S3, GCS)

## Support & Resources

**Official Documentation:**
- [Prometheus](https://prometheus.io/docs/)
- [Loki](https://grafana.com/docs/loki/latest/)
- [Promtail](https://grafana.com/docs/loki/latest/clients/promtail/)
- [Grafana](https://grafana.com/docs/grafana/latest/)

**StorageSage Specific:**
- [Metrics Reference](internal/metrics/README.md)
- [API Documentation](docs/API.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

**Community:**
- GitHub Issues: https://github.com/yourusername/storage-sage/issues
- Discussions: https://github.com/yourusername/storage-sage/discussions
