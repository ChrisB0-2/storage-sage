# StorageSage Observability Stack - Quick Reference

One-page reference for daily operations and troubleshooting.

---

## 🚀 Quick Start Commands

```bash
# Deploy observability stack
./scripts/quickstart-observability.sh

# Verify health
./scripts/verify-observability.sh

# Start/stop
docker compose -f docker-compose.observability.yml up -d
docker compose -f docker-compose.observability.yml down

# View logs
docker compose -f docker-compose.observability.yml logs -f
docker compose -f docker-compose.observability.yml logs -f prometheus
```

---

## 🌐 Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9091 | None |
| Loki | http://localhost:3100 | None |
| Promtail | http://localhost:9080 | None |
| Node Exporter | http://localhost:9100 | None |

---

## 📊 Key Metrics

```promql
# Files deleted (total)
storagesage_files_deleted_total

# Files deleted per minute
rate(storagesage_files_deleted_total[5m]) * 60

# Bytes freed (total)
storagesage_bytes_freed_total

# Free space by path
storage_sage_free_space_percent

# Daemon health
storagesage_daemon_healthy{component="overall"}

# Last cleanup time
storage_sage_cleanup_last_run_timestamp

# Cleanup mode
storage_sage_cleanup_last_mode{mode="AGE|DISK-USAGE|STACK"}

# Error rate
rate(storagesage_errors_total[5m])

# CPU usage
rate(process_cpu_seconds_total{job="storagesage-daemon"}[5m]) * 100

# Memory usage
process_resident_memory_bytes{job="storagesage-daemon"}
```

---

## 🔍 Useful Log Queries

```logql
# All StorageSage logs
{job="storage-sage"}

# Daemon logs only
{job="storage-sage",component="daemon"}

# Backend logs only
{job="storage-sage",component="backend"}

# Error logs
{job="storage-sage"} |= "ERROR"

# Files deleted
{job="storage-sage"} |= "DELETED"

# Cleanup cycles
{job="storage-sage"} |~ "cleanup_mode=(AGE|DISK-USAGE|STACK)"

# Logs from last hour
{job="storage-sage"} | json | __timestamp__ > now() - 1h

# Error rate (per minute)
sum(rate({job="storage-sage"} |= "ERROR" [1m]))
```

---

## 🚨 Alert Status

```bash
# View active alerts
open http://localhost:9091/alerts

# Query via API
curl http://localhost:9091/api/v1/alerts | jq
```

**Critical Alerts:**
- `CriticalDiskSpaceLow` - Free space < 5%
- `DaemonDown` - Daemon unreachable
- `DaemonUnhealthy` - Health check failing
- `StackModeActivated` - Emergency cleanup

**Check alert rules:**
```bash
cat config/prometheus/alerts.yml
```

---

## 🔧 Health Checks

```bash
# Full health verification
./scripts/verify-observability.sh

# Quick checks
curl http://localhost:9091/-/healthy          # Prometheus
curl http://localhost:3100/ready              # Loki
curl http://localhost:9080/ready              # Promtail
curl http://localhost:3001/api/health         # Grafana

# Check Prometheus targets
curl http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | {job, health}'

# Check Loki labels
curl http://localhost:3100/loki/api/v1/labels | jq
```

---

## 🐛 Troubleshooting

### No metrics in Prometheus

```bash
# Check targets
curl http://localhost:9091/api/v1/targets | jq

# Test daemon metrics endpoint
curl http://localhost:9090/metrics | head -20

# Check Prometheus logs
docker logs storagesage-prometheus --tail 50
```

### No logs in Loki

```bash
# Check Promtail status
curl http://localhost:9080/metrics | grep promtail_sent_entries_total

# Check Loki ingestion
curl http://localhost:3100/metrics | grep loki_distributor_lines_received_total

# View Promtail logs
docker logs storagesage-promtail --tail 50
```

### Grafana datasource issues

```bash
# Test Prometheus datasource
docker exec storagesage-grafana wget -O- http://prometheus:9090/api/v1/query?query=up

# Test Loki datasource
docker exec storagesage-grafana wget -O- http://loki:3100/loki/api/v1/labels

# Check datasources config
docker exec storagesage-grafana cat /etc/grafana/provisioning/datasources/datasources.yml
```

### Container not starting

```bash
# Check container status
docker compose -f docker-compose.observability.yml ps

# View logs
docker logs storagesage-prometheus --tail 100
docker logs storagesage-loki --tail 100

# Check config syntax
docker compose -f docker-compose.observability.yml config

# Restart specific service
docker compose -f docker-compose.observability.yml restart prometheus
```

---

## 📁 Important Files

```
storage-sage/
├── docker-compose.observability.yml    # Main stack definition
├── .env.example                        # Environment variables template
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml              # Scrape configs
│   │   └── alerts.yml                  # Alert rules
│   ├── loki/
│   │   └── loki-config.yml             # Loki settings
│   ├── promtail/
│   │   └── promtail-config.yml         # Log collection
│   └── grafana/
│       ├── datasources/
│       │   └── datasources.yml         # Prometheus + Loki
│       └── dashboards/
│           ├── dashboards.yml          # Dashboard config
│           └── storagesage-overview.json
├── scripts/
│   ├── quickstart-observability.sh     # Deploy script
│   └── verify-observability.sh         # Health check script
└── docs/
    ├── OBSERVABILITY.md                # Full documentation
    └── OBSERVABILITY_QUICK_REFERENCE.md # This file
```

---

## 🔄 Common Operations

### Restart Services

```bash
# Restart all
docker compose -f docker-compose.observability.yml restart

# Restart specific service
docker compose -f docker-compose.observability.yml restart prometheus
docker compose -f docker-compose.observability.yml restart loki
docker compose -f docker-compose.observability.yml restart grafana
```

### View Logs

```bash
# All services
docker compose -f docker-compose.observability.yml logs -f

# Specific service
docker compose -f docker-compose.observability.yml logs -f prometheus

# Last 100 lines
docker compose -f docker-compose.observability.yml logs --tail 100
```

### Update Configuration

```bash
# 1. Edit config file
vim config/prometheus/prometheus.yml

# 2. Reload (Prometheus supports hot reload)
curl -X POST http://localhost:9091/-/reload

# OR restart service
docker compose -f docker-compose.observability.yml restart prometheus
```

### Check Resource Usage

```bash
# All containers
docker stats

# Observability stack only
docker stats $(docker ps --filter "name=storagesage-" --format "{{.Names}}")

# Disk usage
docker system df
docker volume ls
```

### Backup Data

```bash
# Prometheus
docker run --rm -v storagesage-prometheus-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/prometheus-$(date +%Y%m%d).tar.gz -C /data .

# Loki
docker run --rm -v storagesage-loki-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/loki-$(date +%Y%m%d).tar.gz -C /data .

# Grafana
docker run --rm -v storagesage-grafana-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/grafana-$(date +%Y%m%d).tar.gz -C /data .
```

### Clean Up

```bash
# Stop all services
docker compose -f docker-compose.observability.yml down

# Remove volumes (WARNING: deletes all data)
docker compose -f docker-compose.observability.yml down -v

# Remove networks
docker network rm storagesage-observability

# Clean up dangling volumes
docker volume prune
```

---

## 📈 Performance Tuning

### Increase Retention

```yaml
# Prometheus (docker-compose.observability.yml)
prometheus:
  command:
    - '--storage.tsdb.retention.time=60d'  # Change from 30d

# Loki (config/loki/loki-config.yml)
limits_config:
  retention_period: 60d  # Change from 30d
```

### Reduce Resource Usage

```yaml
# Prometheus
prometheus:
  deploy:
    resources:
      limits:
        memory: 1g  # Default: 2g
        cpus: '0.5'  # Default: 1
```

### Optimize Queries

```promql
# Use recording rules for expensive queries
# config/prometheus/prometheus.yml
rule_files:
  - '/etc/prometheus/recording_rules.yml'

# Example recording rule
groups:
  - name: storagesage_aggregations
    interval: 30s
    rules:
      - record: job:storagesage_files_deleted:rate5m
        expr: rate(storagesage_files_deleted_total[5m])
```

---

## 🔐 Security Quick Wins

```bash
# 1. Change Grafana password
docker exec -it storagesage-grafana grafana-cli admin reset-admin-password <new-password>

# 2. Bind to localhost only (docker-compose.observability.yml)
ports:
  - "127.0.0.1:3001:3000"  # Grafana
  - "127.0.0.1:9091:9090"  # Prometheus

# 3. Use environment variables for secrets
export GRAFANA_PASSWORD=$(openssl rand -base64 32)

# 4. Enable TLS for Grafana
environment:
  - GF_SERVER_PROTOCOL=https
  - GF_SERVER_CERT_FILE=/etc/grafana/cert.pem
  - GF_SERVER_CERT_KEY=/etc/grafana/key.pem
```

---

## 📞 Support

**Documentation:** [docs/OBSERVABILITY.md](OBSERVABILITY.md)
**Issues:** https://github.com/yourusername/storage-sage/issues
**Scripts:** [scripts/quickstart-observability.sh](../scripts/quickstart-observability.sh)

---

**Last Updated:** 2025-11-23
**Version:** 1.0.0
