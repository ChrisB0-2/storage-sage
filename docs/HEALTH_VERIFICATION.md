# Service Health Monitoring - Verification Commands

## Quick Verification Checklist

```bash
# 1. Verify daemon is running and healthy
systemctl status storage-sage.service
curl -sf http://localhost:9090/health || echo "FAIL: Health endpoint unavailable"

# 2. Check health metrics are exposed
curl -s http://localhost:9090/metrics | grep -E "storagesage_daemon_healthy|storagesage_component_healthy"

# 3. Verify health checks are running
curl -s http://localhost:9090/metrics | grep storagesage_last_health_check_timestamp_seconds

# 4. Confirm no recent restarts
curl -s http://localhost:9090/metrics | grep storagesage_daemon_restarts_total

# 5. Check uptime
curl -s http://localhost:9090/metrics | grep storagesage_daemon_start_timestamp_seconds
```

## Detailed Verification Steps

### 1. Health Metrics Registration

Verify all health metrics are registered with Prometheus:

```bash
# Check all service health metrics exist
METRICS=(
  "storagesage_daemon_healthy"
  "storagesage_daemon_start_timestamp_seconds"
  "storagesage_daemon_restarts_total"
  "storagesage_component_healthy"
  "storagesage_last_health_check_timestamp_seconds"
  "storagesage_health_check_duration_seconds"
  "storagesage_health_check_failures_consecutive"
)

for metric in "${METRICS[@]}"; do
  if curl -s http://localhost:9090/metrics | grep -q "^# HELP $metric"; then
    echo "✓ $metric registered"
  else
    echo "✗ $metric MISSING"
  fi
done
```

**Expected output:**
```
✓ storagesage_daemon_healthy registered
✓ storagesage_daemon_start_timestamp_seconds registered
✓ storagesage_daemon_restarts_total registered
✓ storagesage_component_healthy registered
✓ storagesage_last_health_check_timestamp_seconds registered
✓ storagesage_health_check_duration_seconds registered
✓ storagesage_health_check_failures_consecutive registered
```

### 2. Component Health Checks

Verify all components are reporting health status:

```bash
# List all registered components
curl -s http://localhost:9090/metrics | \
  grep 'storagesage_component_healthy{' | \
  awk -F'component=' '{print $2}' | \
  awk -F',' '{print $1}' | \
  tr -d '"' | \
  sort -u

# Expected components: config, database, metrics_server
```

**Verify each component is healthy (value = 1):**

```bash
curl -s http://localhost:9090/metrics | \
  grep 'storagesage_component_healthy{' | \
  grep -v ' 1$' && echo "FAIL: Unhealthy components found" || echo "PASS: All components healthy"
```

### 3. Health Check Execution

Verify health checks are running on schedule (default: 30s interval):

```bash
# Get timestamp of last health check for each component
echo "Component Health Check Status:"
curl -s http://localhost:9090/metrics | \
  grep 'storagesage_last_health_check_timestamp_seconds{' | \
  while read -r line; do
    component=$(echo "$line" | awk -F'component="' '{print $2}' | awk -F'"' '{print $1}')
    timestamp=$(echo "$line" | awk '{print $NF}')
    age=$(($(date +%s) - ${timestamp%.*}))
    if [ $age -lt 60 ]; then
      echo "✓ $component: checked ${age}s ago"
    else
      echo "✗ $component: checked ${age}s ago (STALE)"
    fi
  done
```

**Expected output:**
```
✓ config: checked 15s ago
✓ database: checked 15s ago
✓ metrics_server: checked 15s ago
```

### 4. Restart Detection

Test restart tracking functionality:

```bash
# Record current restart count
RESTART_BEFORE=$(curl -s http://localhost:9090/metrics | \
  grep 'storagesage_daemon_restarts_total{reason="systemd"}' | \
  awk '{print $NF}')

echo "Restarts before: ${RESTART_BEFORE:-0}"

# Restart service
sudo systemctl restart storage-sage.service
sleep 15  # Wait for startup

# Verify restart was detected
RESTART_AFTER=$(curl -s http://localhost:9090/metrics | \
  grep 'storagesage_daemon_restarts_total{reason="systemd"}' | \
  awk '{print $NF}')

echo "Restarts after: ${RESTART_AFTER:-0}"

if [ "${RESTART_AFTER:-0}" -gt "${RESTART_BEFORE:-0}" ]; then
  echo "✓ PASS: Restart detected and recorded"
else
  echo "✗ FAIL: Restart not detected"
fi
```

### 5. Health Check Duration Metrics

Verify health check duration histograms are recording:

```bash
# Check histogram buckets exist
curl -s http://localhost:9090/metrics | \
  grep 'storagesage_health_check_duration_seconds_bucket' | \
  head -5

# Calculate p95 health check latency
echo "Health check latency (p95):"
curl -s http://localhost:9090/metrics | \
  grep 'storagesage_health_check_duration_seconds_bucket' | \
  awk -F'component="' '{print $2}' | \
  awk -F'"' '{print $1}' | \
  sort -u | \
  while read -r component; do
    echo "  $component: (see Prometheus query)"
  done
```

**Prometheus query for p95:**
```promql
histogram_quantile(0.95, rate(storagesage_health_check_duration_seconds_bucket[5m]))
```

### 6. Overall Health Status

Verify overall health is calculated correctly:

```bash
# Check overall health status
OVERALL_HEALTH=$(curl -s http://localhost:9090/metrics | \
  grep 'storagesage_daemon_healthy{component="overall"}' | \
  awk '{print $NF}')

if [ "$OVERALL_HEALTH" = "1" ]; then
  echo "✓ PASS: Daemon overall health is HEALTHY"
elif [ "$OVERALL_HEALTH" = "0" ]; then
  echo "✗ FAIL: Daemon overall health is UNHEALTHY"
  echo "Component details:"
  curl -s http://localhost:9090/metrics | grep 'storagesage_component_healthy{'
else
  echo "✗ FAIL: Cannot determine health status"
fi
```

### 7. HTTP Health Endpoint

Test the `/health` HTTP endpoint behavior:

```bash
# Test healthy response
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/health)
RESPONSE=$(curl -s http://localhost:9090/health)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✓ PASS: Health endpoint returned 200 OK"
  echo "  Response: $RESPONSE"
else
  echo "✗ FAIL: Health endpoint returned $HTTP_CODE"
  echo "  Response: $RESPONSE"
fi

# Verify JSON response structure
echo "$RESPONSE" | jq -e '.status' > /dev/null 2>&1 && \
  echo "✓ PASS: Response contains 'status' field" || \
  echo "✗ FAIL: Response missing 'status' field"

echo "$RESPONSE" | jq -e '.healthy' > /dev/null 2>&1 && \
  echo "✓ PASS: Response contains 'healthy' field" || \
  echo "✗ FAIL: Response missing 'healthy' field"
```

### 8. Failure Scenario Testing

Simulate component failures to verify detection:

#### Test Database Component Failure

```bash
# Only run if database is enabled
if [ -f /var/lib/storage-sage/deletions.db ]; then
  echo "Testing database failure detection..."

  # Break database permissions
  sudo chmod 000 /var/lib/storage-sage/deletions.db

  # Wait for next health check (30s interval + buffer)
  sleep 35

  # Verify unhealthy state detected
  DB_HEALTH=$(curl -s http://localhost:9090/metrics | \
    grep 'storagesage_component_healthy{component="database"' | \
    awk '{print $NF}')

  if [ "$DB_HEALTH" = "0" ]; then
    echo "✓ PASS: Database failure detected"
  else
    echo "✗ FAIL: Database failure not detected (health=$DB_HEALTH)"
  fi

  # Restore database
  sudo chmod 644 /var/lib/storage-sage/deletions.db

  # Wait for recovery
  sleep 35

  # Verify recovery
  DB_HEALTH=$(curl -s http://localhost:9090/metrics | \
    grep 'storagesage_component_healthy{component="database"' | \
    awk '{print $NF}')

  if [ "$DB_HEALTH" = "1" ]; then
    echo "✓ PASS: Database recovery detected"
  else
    echo "✗ FAIL: Database did not recover (health=$DB_HEALTH)"
  fi
fi
```

#### Test Overall Health Aggregation

```bash
# Force a component failure to test overall health calculation
# (Only works in test environment - DO NOT run in production)

echo "Simulating component failure..."
# This would require modifying config or database to trigger failure
# In production, use controlled maintenance mode instead
```

### 9. Consecutive Failure Tracking

Verify consecutive failure counter increments correctly:

```bash
# Monitor consecutive failures during a simulated failure
echo "Monitoring consecutive failures..."

# Initial state
curl -s http://localhost:9090/metrics | grep 'storagesage_health_check_failures_consecutive{'

# After inducing failure (see test 8), check again
# Should see counter incrementing every 30 seconds
```

### 10. Uptime Calculation

Verify uptime metric is correct:

```bash
# Get daemon start timestamp
START_TIME=$(curl -s http://localhost:9090/metrics | \
  grep '^storagesage_daemon_start_timestamp_seconds ' | \
  awk '{print $NF}')

# Calculate uptime
CURRENT_TIME=$(date +%s)
UPTIME=$((CURRENT_TIME - ${START_TIME%.*}))

echo "Daemon uptime: ${UPTIME}s ($(printf '%dd %dh %dm' $((UPTIME/86400)) $((UPTIME%86400/3600)) $((UPTIME%3600/60))))"

# Verify against systemd
SYSTEMD_UPTIME=$(systemctl show storage-sage.service --property=ActiveEnterTimestamp | \
  awk -F'=' '{print $2}')

echo "Systemd start time: $SYSTEMD_UPTIME"
echo "Metrics start time: $(date -d @${START_TIME%.*})"
```

## Prometheus Query Validation

Verify Prometheus can scrape and query health metrics:

```bash
# Assumes Prometheus is running on localhost:9090

# Query overall health
curl -s 'http://localhost:9090/api/v1/query?query=storagesage_daemon_healthy' | jq .

# Query component health
curl -s 'http://localhost:9090/api/v1/query?query=storagesage_component_healthy' | jq .

# Query restart count
curl -s 'http://localhost:9090/api/v1/query?query=storagesage_daemon_restarts_total' | jq .

# Calculate uptime in PromQL
curl -s 'http://localhost:9090/api/v1/query?query=time()-storagesage_daemon_start_timestamp_seconds' | jq .
```

## Alert Rule Validation

Test that Prometheus alert rules are loaded:

```bash
# Check alert rules are loaded
curl -s http://localhost:9090/api/v1/rules | \
  jq '.data.groups[] | select(.name == "storagesage_service_health") | .rules[] | .name'

# Expected output (list of alert names):
# StorageSageDaemonDown
# StorageSageMetricsMissing
# StorageSageComponentUnhealthy
# StorageSageFrequentRestarts
# ... etc
```

Verify specific alert:

```bash
# Check if any alerts are currently firing
curl -s http://localhost:9090/api/v1/alerts | \
  jq '.data.alerts[] | select(.labels.component == "daemon")'

# Test alert evaluation
curl -s 'http://localhost:9090/api/v1/query?query=ALERTS{alertname="StorageSageDaemonDown"}' | jq .
```

## Grafana Dashboard Validation

```bash
# Verify dashboard JSON is valid
jq empty deploy/grafana/service_health_dashboard.json && \
  echo "✓ PASS: Dashboard JSON is valid" || \
  echo "✗ FAIL: Dashboard JSON is invalid"

# Count panels
PANEL_COUNT=$(jq '.dashboard.panels | length' deploy/grafana/service_health_dashboard.json)
echo "Dashboard contains $PANEL_COUNT panels"

# Expected: 10 panels
if [ "$PANEL_COUNT" -eq 10 ]; then
  echo "✓ PASS: Expected panel count"
else
  echo "✗ FAIL: Expected 10 panels, found $PANEL_COUNT"
fi
```

## Performance Validation

Verify health monitoring has minimal performance impact:

```bash
# Monitor CPU usage during health checks
echo "Monitoring CPU usage (30s)..."
CPU_BEFORE=$(ps -p $(pgrep storage-sage) -o %cpu= | tr -d ' ')
sleep 30  # Wait for at least one health check cycle
CPU_AFTER=$(ps -p $(pgrep storage-sage) -o %cpu= | tr -d ' ')

echo "CPU usage: ${CPU_AFTER}%"

# Health monitoring should add < 0.5% CPU
# Total CPU should remain < 10% (per systemd quota)

# Monitor memory usage
MEM_USAGE=$(ps -p $(pgrep storage-sage) -o rss= | tr -d ' ')
MEM_MB=$((MEM_USAGE / 1024))

echo "Memory usage: ${MEM_MB}MB"

# Health checker should add < 5MB
# Total memory should remain < 512MB (per systemd limit)
```

## Integration Test Suite

Complete end-to-end test:

```bash
#!/bin/bash
set -e

echo "=== StorageSage Health Monitoring Integration Test ==="

# 1. Verify service is running
echo "1. Checking service status..."
systemctl is-active storage-sage.service || exit 1

# 2. Verify metrics endpoint
echo "2. Verifying metrics endpoint..."
curl -sf http://localhost:9090/metrics > /dev/null || exit 1

# 3. Verify health endpoint
echo "3. Verifying health endpoint..."
curl -sf http://localhost:9090/health > /dev/null || exit 1

# 4. Verify all health metrics present
echo "4. Verifying health metrics..."
for metric in daemon_healthy daemon_start_timestamp component_healthy; do
  curl -s http://localhost:9090/metrics | grep -q "storagesage_${metric}" || exit 1
done

# 5. Verify components are healthy
echo "5. Verifying component health..."
UNHEALTHY=$(curl -s http://localhost:9090/metrics | \
  grep 'storagesage_component_healthy{' | \
  grep ' 0$' | \
  wc -l)

if [ "$UNHEALTHY" -gt 0 ]; then
  echo "FAIL: $UNHEALTHY unhealthy components"
  exit 1
fi

# 6. Verify health checks are recent
echo "6. Verifying health checks are recent..."
CURRENT=$(date +%s)
curl -s http://localhost:9090/metrics | \
  grep 'storagesage_last_health_check_timestamp_seconds{' | \
  while read -r line; do
    TS=$(echo "$line" | awk '{print $NF}')
    AGE=$((CURRENT - ${TS%.*}))
    if [ $AGE -gt 60 ]; then
      echo "FAIL: Stale health check (${AGE}s old)"
      exit 1
    fi
  done

# 7. Test restart detection
echo "7. Testing restart detection..."
BEFORE=$(curl -s http://localhost:9090/metrics | \
  grep 'storagesage_daemon_restarts_total{reason="systemd"}' | \
  awk '{print $NF}')

sudo systemctl restart storage-sage.service
sleep 15

AFTER=$(curl -s http://localhost:9090/metrics | \
  grep 'storagesage_daemon_restarts_total{reason="systemd"}' | \
  awk '{print $NF}')

if [ "${AFTER:-0}" -le "${BEFORE:-0}" ]; then
  echo "FAIL: Restart not detected"
  exit 1
fi

echo ""
echo "=== ALL TESTS PASSED ==="
```

## Troubleshooting Commands

### Debug health check failures

```bash
# View recent health-related log entries
sudo journalctl -u storage-sage.service --since "5 minutes ago" | grep -i health

# Check for health check timeouts
curl -s http://localhost:9090/metrics | grep storagesage_health_check_timeouts_total

# View health check durations
curl -s http://localhost:9090/metrics | grep storagesage_health_check_duration_seconds_sum
```

### Investigate restart events

```bash
# View all restart events in systemd
sudo journalctl -u storage-sage.service | grep -i "Starting\|Stopped\|restart"

# Check restart counter by reason
curl -s http://localhost:9090/metrics | grep storagesage_daemon_restarts_total

# View systemd service history
systemctl status storage-sage.service
```

### Validate alert configuration

```bash
# Test alert rule syntax
promtool check rules deploy/prometheus/storagesage_alerts.yml

# Simulate alert condition
# (Manually set metric to trigger alert for testing)
```

## Continuous Monitoring

Set up continuous validation (add to cron or monitoring system):

```bash
# /etc/cron.hourly/check-storagesage-health
#!/bin/bash
HEALTH=$(curl -sf http://localhost:9090/health | jq -r '.healthy')
if [ "$HEALTH" != "true" ]; then
  echo "ALERT: StorageSage health check failed"
  # Send notification
fi
```

## Success Criteria

All verification steps should show:
- ✓ All health metrics registered
- ✓ All components reporting healthy status
- ✓ Health checks executing every 30 seconds
- ✓ Restart detection working
- ✓ Health endpoint returning 200 OK
- ✓ Prometheus scraping successfully
- ✓ Alert rules loaded
- ✓ Grafana dashboard displays data
- ✓ Performance impact < 1% CPU, < 5MB memory
