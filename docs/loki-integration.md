# Grafana Loki Integration for StorageSage

## Architecture Overview

StorageSage integrates with Grafana Loki to provide efficient log aggregation, querying, and alerting for cleanup operations.

### Component Diagram

```
StorageSage Daemon
    │
    ├─→ /var/log/storage-sage/cleanup.log
    │                           │
    │                           ├─→ File Parser API → React Frontend (existing)
    │                           │
    │                           └─→ Promtail → Loki → Grafana (new)
    │
    └─→ Prometheus Metrics (existing)
```

### Data Flow

1. **Log Generation**: StorageSage daemon writes structured logs to `/var/log/storage-sage/cleanup.log`
2. **Log Shipping**: Promtail tails the log file and ships entries to Loki
3. **Log Storage**: Loki indexes and stores logs with labels for efficient querying
4. **Visualization**: Grafana queries Loki to display dashboards and trigger alerts

### Relationship to Existing Systems

- **File-based API**: Remains unchanged. The React frontend continues to use the file parser API
- **Prometheus Metrics**: Continues to operate independently for metrics
- **Log Format**: No changes required to existing log format

## Deployment Instructions

### Prerequisites

- Docker and Docker Compose installed
- StorageSage daemon running and generating logs
- Ports available: 3100 (Loki), 9080 (Promtail), 3001 (Grafana)

### Docker Compose Deployment

1. **Ensure configuration files exist**:
   ```bash
   ls -la promtail-config.yml loki-config.yml
   ```

2. **Start the Loki stack**:
   ```bash
   ./scripts/deploy-loki.sh
   ```

   Or manually:
   ```bash
   docker compose up -d loki promtail
   ```

3. **Verify services are running**:
   ```bash
   docker ps | grep -E "loki|promtail"
   ```

4. **Check health**:
   ```bash
   curl http://localhost:3100/ready  # Loki
   curl http://localhost:9080/ready  # Promtail
   ```

### Production Deployment (Systemd)

For production, run Loki and Promtail as systemd services:

**`/etc/systemd/system/loki.service`**:
```ini
[Unit]
Description=Grafana Loki
After=network.target

[Service]
Type=simple
User=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/config.yml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**`/etc/systemd/system/promtail.service`**:
```ini
[Unit]
Description=Promtail
After=network.target loki.service
Requires=loki.service

[Service]
Type=simple
User=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Network Requirements

- **Loki**: Port 3100 (HTTP API)
- **Promtail**: Port 9080 (HTTP metrics)
- **Grafana**: Port 3001 (Web UI)
- All services communicate on Docker network `storage-sage-network`

### Firewall Rules

If using a firewall, allow:
```bash
# Loki API
sudo ufw allow 3100/tcp

# Grafana
sudo ufw allow 3001/tcp
```

## Query Examples

### Basic Queries

**All deletion logs (last hour)**:
```logql
{job="storage-sage"}
```

**Only DELETE actions**:
```logql
{job="storage-sage", action="DELETE"}
```

**Errors only**:
```logql
{job="storage-sage", action="ERROR"}
```

### Aggregation Queries

**Deletion count per hour**:
```logql
sum(count_over_time({job="storage-sage", action="DELETE"}[1h]))
```

**Deletion rate (per minute)**:
```logql
sum(rate({job="storage-sage", action="DELETE"}[5m])) * 60
```

**Space freed (requires size extraction)**:
```logql
sum(sum_over_time({job="storage-sage", action="DELETE"} | regexp `size=(?P<size>\d+)` [24h]))
```

### Filtered Queries

**By primary reason**:
```logql
{job="storage-sage", primary_reason="stacked_cleanup"}
```

**By object type**:
```logql
{job="storage-sage", object_type="file"}
```

**Combined filters**:
```logql
{job="storage-sage", action="DELETE", primary_reason="age_threshold", object_type="file"}
```

### Time Range Queries

**Last 24 hours**:
```logql
{job="storage-sage"} [24h]
```

**Specific time range**:
```logql
{job="storage-sage"} [2024-01-15T00:00:00Z, 2024-01-16T00:00:00Z]
```

### Performance Optimization Tips

1. **Use label filters first**: Always filter by `job`, `action`, `object_type` before parsing
2. **Limit result sets**: Use `limit` parameter in queries
3. **Use time ranges**: Narrow time windows improve performance
4. **Index labels**: Ensure frequently queried fields are labels, not parsed fields

## Dashboard Guide

### Panel Explanations

1. **Deletion Rate Gauge**: Current deletions per minute (5-minute average)
   - Green: <10/min (normal)
   - Yellow: 10-50/min (moderate activity)
   - Red: >50/min (high activity or spike)

2. **Space Freed Today**: Total MB freed in last 24 hours
   - Useful for tracking cleanup effectiveness

3. **Deletion Reasons Distribution**: Pie chart showing why files were deleted
   - `age_threshold`: Files older than configured age
   - `disk_threshold`: Disk usage exceeded threshold
   - `combined`: Both age and disk conditions met
   - `stacked_cleanup`: Emergency cleanup mode (>98% disk usage)

4. **Hourly Deletion Timeline**: Time series of deletion activity
   - Identify patterns and peak cleanup times

5. **Action Type Distribution**: Breakdown of DELETE, SKIP, ERROR, DRY_RUN
   - High SKIP rate may indicate NFS issues
   - High ERROR rate requires investigation

6. **Top 10 Deleted Paths**: Most frequently deleted paths
   - Helps identify problematic directories

7. **Error Log Stream**: Real-time error log viewer
   - Filter by time range to investigate issues

8. **Space Freed by Reason**: MB freed grouped by deletion reason
   - Shows which cleanup triggers are most effective

9. **Stacked Cleanup Activity**: Time series with alert threshold
   - Any value >0 indicates critical disk condition
   - Triggers alert automatically

10. **Average File Size Deleted**: Average size of deleted files
    - Helps understand cleanup patterns

### Common Patterns to Watch

- **Sudden spike in deletions**: Possible misconfiguration or emergency cleanup
- **High skip rate**: NFS stale handles or permission issues
- **Stacked cleanup events**: Critical disk condition requiring immediate attention
- **Zero deletions for extended period**: Daemon may be stopped or not processing

## Alert Runbooks

### High Error Rate

**Condition**: >10 errors in 5 minutes

**Diagnosis Steps**:
1. Check error log stream in Grafana
2. Review error messages for common patterns
3. Check NFS mount health: `df -h` and `mount | grep nfs`
4. Verify file permissions on target paths
5. Check daemon logs: `docker logs storage-sage-daemon`

**Remediation**:
- If NFS-related: Check NFS server health, remount if needed
- If permission-related: Review path permissions and daemon user
- If path-related: Verify paths are within allowed scan paths

**Escalation**: If errors persist >15 minutes, escalate to infrastructure team

### Stacked Cleanup Triggered

**Condition**: Any stacked_cleanup event detected

**Severity**: CRITICAL

**Diagnosis Steps**:
1. Immediately check disk usage: `df -h`
2. Verify disk usage exceeds 98% threshold
3. Review cleanup configuration for target free space
4. Check if cleanup is actively running: `docker logs storage-sage-daemon --tail 100`

**Remediation**:
1. Verify cleanup daemon is running and processing files
2. If daemon is stuck, restart: `docker restart storage-sage-daemon`
3. Manually trigger cleanup if needed
4. Consider increasing cleanup aggressiveness temporarily
5. Monitor space freed metrics in Grafana

**Escalation**: Page on-call engineer immediately. This indicates critical disk condition.

### No Deletions for 1 Hour

**Condition**: Zero DELETE actions in 1 hour

**Diagnosis Steps**:
1. Check daemon health: `docker ps | grep storage-sage-daemon`
2. Verify daemon is running: `docker logs storage-sage-daemon --tail 50`
3. Check if there are files to delete (scan paths may be clean)
4. Review configuration for age/disk thresholds
5. Check Prometheus metrics: `curl http://localhost:9090/metrics | grep storagesage`

**Remediation**:
- If daemon stopped: Restart service
- If no candidates: Verify scan paths and thresholds are correct
- If configuration issue: Review and update config

**Escalation**: If daemon is down and cannot be restarted, escalate to operations

### Excessive Skip Rate

**Condition**: >50% of operations are SKIP

**Diagnosis Steps**:
1. Query skipped entries: `{job="storage-sage", action="SKIP"}`
2. Check for NFS stale patterns in skip reasons
3. Verify NFS mount health
4. Check file permissions on scan paths
5. Review path allowlist configuration

**Remediation**:
- NFS issues: Remount NFS, check server health
- Permission issues: Fix file/directory permissions
- Path issues: Review and update allowed paths in config

**Escalation**: If >80% skip rate persists, escalate to infrastructure

### Deletion Rate Spike

**Condition**: >100 deletions/minute

**Diagnosis Steps**:
1. Check recent configuration changes
2. Review deletion timeline for sudden increase
3. Check if stacked cleanup was triggered
4. Verify disk usage thresholds
5. Review what paths are being cleaned

**Remediation**:
- If misconfiguration: Revert recent config changes
- If emergency cleanup: Monitor until disk usage normalizes
- If unexpected: Review scan paths and thresholds

**Escalation**: If rate >500/min, investigate immediately for possible data loss

## Troubleshooting

### Logs Not Appearing in Loki

**Symptoms**: Dashboard shows no data, queries return empty results

**Diagnosis**:
1. Check Promtail is running: `docker ps | grep promtail`
2. Check Promtail logs: `docker logs storage-sage-promtail`
3. Verify log file exists: `ls -la /var/log/storage-sage/cleanup.log`
4. Check Promtail can read log: `docker exec storage-sage-promtail cat /var/log/storage-sage/cleanup.log | head`
5. Verify Loki connectivity: `docker exec storage-sage-promtail wget -O- http://loki:3100/ready`

**Solutions**:
- Restart Promtail: `docker restart storage-sage-promtail`
- Check volume mounts in docker-compose.yml
- Verify file permissions (Promtail needs read access)

### Slow Query Performance

**Symptoms**: Queries take >5 seconds, dashboard panels timeout

**Solutions**:
1. Narrow time range (use shorter intervals)
2. Add more label filters (action, object_type, etc.)
3. Reduce result limits
4. Check Loki resource usage: `docker stats storage-sage-loki`
5. Increase Loki memory if needed

### Parsing Errors

**Symptoms**: Labels not extracted, primary_reason missing

**Diagnosis**:
1. Check Promtail config: `docker exec storage-sage-promtail cat /etc/promtail/config.yml`
2. Test regex pattern against sample log line
3. Review Promtail logs for parsing errors

**Solutions**:
- Verify regex pattern matches actual log format
- Check for log format changes in StorageSage
- Update Promtail config if log format changed

### High Memory Usage

**Symptoms**: Loki container using >512MB RAM

**Solutions**:
1. Reduce retention period (if acceptable)
2. Increase chunk flush interval
3. Reduce max query length
4. Add resource limits in docker-compose.yml

## Maintenance Procedures

### Log Retention Management

**Current retention**: 7 days (168 hours)

**To change retention**:
1. Edit `loki-config.yml`:
   ```yaml
   limits_config:
     reject_old_samples_max_age: 168h  # Change to desired retention
   ```
2. Restart Loki: `docker restart storage-sage-loki`

**To manually delete old logs**:
```bash
# Loki will automatically delete based on retention policy
# Manual deletion not recommended
```

### Loki Compaction

Loki automatically compacts data. Monitor compaction status:
```bash
docker logs storage-sage-loki | grep -i compact
```

### Dashboard Updates

1. Export current dashboard from Grafana UI
2. Save to `grafana/dashboards/storage-sage-deletion-analytics.json`
3. Restart Grafana to reload (if using provisioning)

### Alert Rule Modifications

1. Edit `storage-sage-alerts.yml`
2. Restart Loki: `docker restart storage-sage-loki`
3. Verify rules loaded: Check Loki ruler API

### Backup and Restore

**Backup**:
```bash
./scripts/backup-loki.sh
```

**Restore**:
```bash
# Restore data volume
docker run --rm \
  -v storage-sage-loki-data:/data \
  -v /path/to/backup:/backup \
  alpine tar xzf /backup/loki-data-TIMESTAMP.tar.gz -C /data

# Restore configs
tar xzf backups/loki-configs-TIMESTAMP.tar.gz -C /path/to/project
```

## Health Checks

### Service Health

```bash
# Loki
curl http://localhost:3100/ready
curl http://localhost:3100/metrics

# Promtail
curl http://localhost:9080/ready
curl http://localhost:9080/metrics

# Grafana
curl http://localhost:3001/api/health
```

### Log Ingestion Test

```bash
# Generate test log entry (if StorageSage is running)
# Then query Loki:
curl -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="storage-sage"}' \
  --data-urlencode 'start='$(date -d '5 minutes ago' +%s)000000000 \
  --data-urlencode 'end='$(date +%s)000000000
```

## Performance Tuning

### For High-Volume Environments

1. **Increase batch sizes** in Promtail:
   ```yaml
   clients:
     - batchsize: 2097152  # 2MB
   ```

2. **Increase Loki ingestion limits**:
   ```yaml
   limits_config:
     ingestion_rate_mb: 32
     ingestion_burst_size_mb: 64
   ```

3. **Adjust chunk settings**:
   ```yaml
   ingester:
     chunk_idle_period: 10m
     chunk_retain_period: 30s
   ```

## References

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Syntax](https://grafana.com/docs/loki/latest/logql/)
- [Promtail Configuration](https://grafana.com/docs/loki/latest/clients/promtail/configuration/)
- [StorageSage Main Documentation](../README.md)

