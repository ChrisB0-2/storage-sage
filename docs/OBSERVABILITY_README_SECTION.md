# Observability Stack Integration - README Section

This content should be added to the main README.md file in the "Monitoring & Alerting" section.

---

## Observability Stack (Production-Grade Monitoring)

StorageSage includes a complete, production-ready observability stack based on industry-standard tools:

- **Prometheus** - Metrics collection and time-series database
- **Loki** - Log aggregation and querying
- **Promtail** - Log shipping agent
- **Grafana** - Unified visualization and dashboards
- **Node Exporter** - System-level metrics

### Quick Start

Deploy the complete monitoring stack with one command:

```bash
# One-command deployment
./scripts/quickstart-observability.sh

# Verify health
./scripts/verify-observability.sh
```

Access points after deployment:

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana Dashboards | http://localhost:3001 | admin / admin |
| Prometheus Metrics | http://localhost:9091 | None |
| Loki Logs | http://localhost:3100 | None |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Observability Stack                          │
│                                                              │
│  StorageSage Services (Daemon, Backend, Frontend)           │
│         │                                                    │
│         ├─ Metrics ──→ Prometheus ──┐                       │
│         │                            │                       │
│         └─ Logs ────→ Promtail ──→ Loki ──┐                │
│                                             │                │
│                                    Grafana ←┘                │
│                                  (Visualization)             │
│                                                              │
│  System Metrics: Node Exporter ──→ Prometheus               │
└─────────────────────────────────────────────────────────────┘
```

### Features

**Metrics Collection (Prometheus)**
- All StorageSage services auto-discovered and scraped
- 15-second scrape interval
- 30-day retention
- Pre-configured alerting rules

**Log Aggregation (Loki + Promtail)**
- Automatic log collection from all Docker containers
- System log integration (`/var/log`)
- Structured log parsing (JSON, regex)
- Label-based querying
- 30-day retention

**Visualization (Grafana)**
- Pre-built "StorageSage Overview" dashboard
- Auto-provisioned datasources (Prometheus + Loki)
- Real-time metrics and logs in one view
- No manual configuration required

### Pre-configured Dashboards

**StorageSage Overview Dashboard** includes:
- Free space gauges (per path, color-coded thresholds)
- Files deleted rate (time series)
- Total bytes freed (cumulative)
- Daemon health status
- Last cleanup timestamp
- Live log stream with filtering

### Metrics Exposed

StorageSage exposes comprehensive Prometheus metrics:

**Core Cleanup Metrics:**
```promql
storagesage_files_deleted_total           # Files deleted counter
storagesage_bytes_freed_total             # Bytes freed counter
storage_sage_free_space_percent{path}     # Free space by path
storage_sage_cleanup_last_run_timestamp   # Last cleanup time
storage_sage_cleanup_last_mode{mode}      # Cleanup mode (AGE/DISK-USAGE/STACK)
storage_sage_path_bytes_deleted_total{path} # Bytes deleted per path
```

**Health & Performance:**
```promql
storagesage_daemon_healthy{component}           # Daemon health status
storagesage_component_healthy{component}        # Component health
storagesage_health_check_duration_seconds       # Health check latency
storagesage_cleanup_duration_seconds            # Cleanup cycle duration
storagesage_errors_total                        # Error counter
```

**Resource Usage:**
```promql
process_cpu_seconds_total{job="storagesage-daemon"}    # CPU usage
process_resident_memory_bytes{job="storagesage-daemon"} # Memory usage
go_goroutines{job="storagesage-daemon"}                 # Goroutine count
```

### Example Queries

**Prometheus (PromQL):**
```promql
# Files deleted per minute (5min rate)
rate(storagesage_files_deleted_total[5m]) * 60

# Total bytes freed (human-readable)
storagesage_bytes_freed_total

# Free space by path
storage_sage_free_space_percent

# Average cleanup duration
rate(storagesage_cleanup_duration_seconds_sum[5m]) /
rate(storagesage_cleanup_duration_seconds_count[5m])

# Error rate (errors per second)
rate(storagesage_errors_total[5m])
```

**Loki (LogQL):**
```logql
# All StorageSage logs
{job="storage-sage"}

# Daemon errors only
{job="storage-sage",component="daemon"} |= "ERROR"

# Files deleted (from logs)
{job="storage-sage"} |= "DELETED"

# Cleanup mode distribution
{job="storage-sage"} |~ "cleanup_mode=(AGE|DISK-USAGE|STACK)"
```

### Alerting

Pre-configured Prometheus alerts (in `config/prometheus/alerts.yml`):

**Critical:**
- `CriticalDiskSpaceLow` - Free space < 5%
- `DaemonDown` - Daemon unreachable
- `DaemonUnhealthy` - Health checks failing
- `StackModeActivated` - Emergency cleanup triggered

**Warning:**
- `LowDiskSpace` - Free space < 10%
- `NoRecentCleanup` - No cleanup in 1 hour
- `CleanupFailureRate` - Elevated errors
- `HighCPUUsage` - Daemon CPU > 50%
- `HighMemoryUsage` - Daemon memory > 1GB

**System:**
- `HighSystemCPU` - Host CPU > 80%
- `HighSystemMemory` - Host memory > 90%
- `DiskIOSaturation` - I/O saturation

View active alerts: http://localhost:9091/alerts

### Manual Deployment

```bash
# 1. Set environment variables
export USER_ID=$(id -u)
cp .env.example .env

# 2. Start observability stack
docker compose -f docker-compose.observability.yml up -d

# 3. Verify all services are healthy
./scripts/verify-observability.sh

# 4. Access Grafana
open http://localhost:3001
# Login: admin / admin
```

### Integration with Existing Services

The observability stack auto-discovers StorageSage services via Docker networks:

**Metrics Scraping:**
- Daemon: `http://storage-sage-daemon:9090/metrics`
- Backend: `http://storage-sage-backend:9090/metrics`
- Node Exporter: `http://localhost:9100/metrics`

**Log Collection:**
- All containers with `storagesage` in the name
- System logs from `/var/log`
- Automatic labeling: `job="storage-sage"`, `component="daemon|backend"`

### Scaling & Performance

**Resource Usage (typical):**
- Prometheus: ~500MB RAM, 2-5% CPU
- Loki: ~300MB RAM, 1-3% CPU
- Promtail: ~100MB RAM, 1-2% CPU
- Grafana: ~200MB RAM, 1-2% CPU
- Node Exporter: ~20MB RAM, <1% CPU

**Total overhead:** ~1.1GB RAM, 5-10% CPU

**Scaling recommendations:**
- Small deployments (<1TB): Default settings
- Medium (1-10TB): Increase Prometheus retention to 60d
- Large (10TB+): Enable remote write to centralized Prometheus
- Very large: Use Prometheus federation + Thanos/Cortex

### Troubleshooting

**No metrics appearing:**
```bash
# Check Prometheus targets
curl http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | {job, health}'

# Verify daemon metrics endpoint
curl http://localhost:9090/metrics | grep storagesage_
```

**No logs in Loki:**
```bash
# Check Promtail is running
docker logs storagesage-promtail

# Verify Loki ingestion
curl http://localhost:3100/metrics | grep loki_distributor_lines_received_total

# Test log query
curl -G http://localhost:3100/loki/api/v1/query \
  --data-urlencode 'query={job="storage-sage"}' | jq
```

**Grafana datasources not connecting:**
```bash
# Test Prometheus datasource
docker exec storagesage-grafana wget -O- http://prometheus:9090/api/v1/query?query=up

# Test Loki datasource
docker exec storagesage-grafana wget -O- http://loki:3100/loki/api/v1/labels
```

### Advanced Configuration

**Custom retention periods:**
```yaml
# docker-compose.observability.yml
prometheus:
  command:
    - '--storage.tsdb.retention.time=60d'  # 60 days instead of 30

# config/loki/loki-config.yml
limits_config:
  retention_period: 60d  # 60 days instead of 30
```

**Enable Alertmanager integration:**
```bash
# Add Alertmanager service to docker-compose.observability.yml
# Configure in config/prometheus/prometheus.yml:
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

**Remote write (federation):**
```yaml
# config/prometheus/prometheus.yml
remote_write:
  - url: "https://prometheus-remote.example.com/api/v1/write"
    basic_auth:
      username: "storagesage"
      password_file: /etc/prometheus/remote_password
```

### Files & Configuration

**Docker Compose:**
- [docker-compose.observability.yml](docker-compose.observability.yml) - Full stack definition

**Configuration Files:**
- [config/prometheus/prometheus.yml](config/prometheus/prometheus.yml) - Scrape configs
- [config/prometheus/alerts.yml](config/prometheus/alerts.yml) - Alert rules
- [config/loki/loki-config.yml](config/loki/loki-config.yml) - Loki settings
- [config/promtail/promtail-config.yml](config/promtail/promtail-config.yml) - Log collection
- [config/grafana/datasources/](config/grafana/datasources/) - Auto-provisioned datasources
- [config/grafana/dashboards/](config/grafana/dashboards/) - Pre-built dashboards

**Scripts:**
- [scripts/quickstart-observability.sh](scripts/quickstart-observability.sh) - One-command deployment
- [scripts/verify-observability.sh](scripts/verify-observability.sh) - Health verification

**Documentation:**
- [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) - Complete observability guide

### Production Checklist

Before deploying to production:

- [ ] Change Grafana default password (`GRAFANA_PASSWORD` in `.env`)
- [ ] Configure retention periods for your environment
- [ ] Set up Alertmanager for alert routing (Slack, PagerDuty, email)
- [ ] Enable TLS for Grafana (if exposed externally)
- [ ] Configure backup strategy for Prometheus/Loki data
- [ ] Set resource limits appropriate for your workload
- [ ] Review and customize alerting thresholds
- [ ] Integrate with your existing monitoring infrastructure (if any)
- [ ] Set up log rotation for Promtail positions file
- [ ] Document runbook procedures for alert response

### Pattern Credit

This observability stack is based on the proven architecture from [maiobarbero/grafana-prometheus-loki](https://github.com/maiobarbero/grafana-prometheus-loki), adapted and extended for StorageSage with:

- Service auto-discovery for StorageSage components
- Custom metrics and alert rules for storage cleanup operations
- Pre-built dashboards tailored to storage management workflows
- Integration with StorageSage's existing metrics infrastructure
- Production-grade configuration with security hardening

---

**Related Sections:**
- See [Monitoring & Alerting](#monitoring--alerting) for basic metrics access
- See [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) for complete documentation
