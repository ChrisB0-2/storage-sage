# StorageSage Setup Guide

Complete documentation for installing and configuring StorageSage on your own system.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Installation Methods](#installation-methods)
4. [Configuration](#configuration)
5. [First Run](#first-run)
6. [Verification](#verification)
7. [Adding Custom Paths](#adding-custom-paths)
8. [Monitoring & Observability](#monitoring--observability)
9. [Security](#security)
10. [Troubleshooting](#troubleshooting)
11. [Production Deployment](#production-deployment)

---

## Prerequisites

### Required
- **Docker** 20.10+ and **Docker Compose** 2.0+
- **Linux/macOS** system (tested on Linux, should work on macOS)
- **Minimum 2GB RAM** (StorageSage uses ~50MB, but Docker needs overhead)
- **Port availability**: 8443 (API), 9090 (Prometheus), 3100 (Loki)

### Optional
- **Go 1.24+** (if building from source)
- **Node.js 18+** (if building frontend from source)
- **Git** (for cloning repository)

### Check Prerequisites

```bash
# Check Docker
docker --version
docker-compose --version

# Check available ports
sudo netstat -tlnp | grep -E ':(8443|9090|3100)'

# Check disk space (need at least 5GB for containers + images)
df -h
```

---

## Quick Start

### Option 1: Docker Compose (Recommended)

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/storage-sage.git
cd storage-sage

# 2. Start all services
docker-compose up -d

# 3. Wait 10 seconds for services to initialize
sleep 10

# 4. Open the web interface
open https://localhost:8443
# Or: xdg-open https://localhost:8443  (Linux)

# Default credentials:
# Username: admin
# Password: changeme
```

**That's it!** StorageSage is now running.

---

## Installation Methods

### Method 1: Docker Compose (Production-Ready)

Best for most users. Includes all services with proper networking and persistence.

```bash
# Start with all observability features
docker-compose --profile grafana up -d

# Or start minimal (daemon + backend + frontend)
docker-compose up -d

# Check status
docker-compose ps
```

**Services Started:**
- `storage-sage-daemon` - Core cleanup daemon
- `storage-sage-backend` - REST API server
- `storage-sage-frontend` - React web UI (via nginx)
- `loki` - Log aggregation
- `promtail` - Log shipping
- `prometheus` - Metrics collection
- `grafana` - Dashboards (with `--profile grafana`)

### Method 2: Helper Script

```bash
# All-in-one script with options
./scripts/start.sh --mode docker --all

# Options:
#   --mode docker    : Use Docker Compose
#   --mode local     : Build and run locally
#   --all            : Include Grafana
#   --dry-run        : Enable dry-run mode (simulate only)
```

### Method 3: Build from Source

```bash
# Build daemon
cd cmd/storage-sage
go build -o storage-sage-daemon

# Build backend
cd ../../web/backend
go build -o storage-sage-backend

# Build frontend
cd ../frontend
npm install
npm run build

# Run manually
./storage-sage-daemon \
  --config /path/to/config.yaml \
  --db /var/lib/storage-sage/deletions.db
```

---

## Configuration

### Core Configuration File

Location: `web/config/config.yaml`

```yaml
# === PATHS TO SCAN ===
scan_paths:
    - /test-workspace              # Add your paths here
    - /tmp/storage-sage-test-workspace
    # - /var/log                   # Example: system logs
    # - /home/user/downloads       # Example: user downloads
    # - /data/backups              # Example: backup directory

# === GLOBAL DEFAULTS ===
min_free_percent: 10               # Minimum free space threshold
age_off_days: 7                    # Default age for file deletion
interval_minutes: 1                # Cleanup interval (1-60 minutes)

# === PATH-SPECIFIC RULES ===
paths:
    - path: /test-workspace
      age_off_days: 7              # Delete files older than 7 days
      min_free_percent: 5          # Trigger cleanup at 5% free
      max_free_percent: 90         # Stop cleanup at 90% free
      target_free_percent: 80      # Try to reach 80% free
      priority: 1                  # Higher = delete first
      stack_threshold: 95          # Emergency mode at 95% full
      stack_age_days: 14           # In emergency, delete files >14 days

    - path: /tmp/storage-sage-test-workspace
      age_off_days: 7
      min_free_percent: 5
      max_free_percent: 90
      target_free_percent: 80
      priority: 1
      stack_threshold: 95
      stack_age_days: 14

# === OBSERVABILITY ===
prometheus:
    port: 9090                     # Prometheus metrics port

logging:
    rotation_days: 30              # Keep logs for 30 days

# === RESOURCE LIMITS ===
resource_limits:
    max_cpu_percent: 10            # Max CPU usage

# === CLEANUP OPTIONS ===
cleanup_options:
    recursive: true                # Scan subdirectories
    delete_dirs: false             # Don't delete directories

# === PERFORMANCE TUNING ===
scan_optimizations:
    fast_scan_threshold: 1000000   # Files before using fast scan
    cache_ttl_minutes: 5           # Cache validity duration
    parallel_scans: false          # Enable parallel scanning
    use_fast_scan: false           # Skip detailed file inspection
    use_cache: false               # Cache scan results

worker_pool:
    enabled: false                 # Enable worker pool
    concurrency: 5                 # Parallel workers
    batch_size: 100                # Files per batch
    timeout_seconds: 30            # Worker timeout

# === DATABASE ===
nfs_timeout_seconds: 5             # Network filesystem timeout
database_path: /var/lib/storage-sage/deletions.db
```

### Understanding the Three Cleanup Modes

StorageSage automatically chooses the right mode based on disk usage:

#### 1. **AGE Mode** (Routine Maintenance)
- **When**: Disk usage below `min_free_percent`
- **What**: Deletes files older than `age_off_days`
- **Example**: Delete files older than 7 days

#### 2. **DISK-USAGE Mode** (Proactive)
- **When**: Disk usage above `min_free_percent`
- **What**: Deletes oldest files until reaching `target_free_percent`
- **Example**: Free up space to reach 80% free

#### 3. **STACK Mode** (Emergency)
- **When**: Disk usage above `stack_threshold` (e.g., 95% full)
- **What**: Aggressively deletes files older than `stack_age_days`
- **Example**: Delete ALL files older than 14 days to prevent disk full

### Path-Specific Rules

You can configure different rules for different directories:

```yaml
paths:
    # Critical system logs - long retention
    - path: /var/log
      age_off_days: 30             # Keep for 30 days
      priority: 3                  # Lower priority (delete last)

    # Temporary downloads - short retention
    - path: /home/user/downloads
      age_off_days: 3              # Delete after 3 days
      priority: 1                  # High priority (delete first)

    # Old backups - emergency only
    - path: /data/backups
      age_off_days: 90             # Keep for 90 days normally
      stack_age_days: 30           # But delete >30 days in emergency
      priority: 2                  # Medium priority
```

---

## First Run

### Step 1: Create Test Workspace

```bash
# Create directories that StorageSage will monitor
mkdir -p /tmp/storage-sage-test-workspace/var/log
chmod 755 /tmp/storage-sage-test-workspace
```

### Step 2: Start Services

```bash
# Start all services
docker-compose up -d

# Check logs
docker-compose logs -f storage-sage-daemon
```

Expected output:
```
INFO: StorageSage daemon starting...
INFO: Loaded configuration from /etc/storage-sage/config.yaml
INFO: Scanning paths: [/test-workspace, /tmp/storage-sage-test-workspace]
INFO: Cleanup interval: 1 minutes
INFO: Starting cleanup cycle...
```

### Step 3: Access Web Interface

```bash
# Open browser to:
https://localhost:8443

# Your browser will warn about self-signed certificate
# Click "Advanced" -> "Proceed to localhost"

# Login with default credentials:
Username: admin
Password: changeme
```

### Step 4: Create Test Files (Optional)

```bash
# Run the test file generator
./scripts/create_test_files.sh

# This creates:
# - 10 old files (15 days old)
# - 5 large files (50MB each, 20 days old)
# - 5 recent files (1 day old - should be kept)
```

### Step 5: Verify Cleanup

Wait 1-2 minutes for the automatic cleanup cycle, or trigger manually:

```bash
# Get authentication token
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' | jq -r '.token')

# Trigger manual cleanup
curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger
```

Check the dashboard - you should see:
- Files Deleted: **15** (old + large files)
- Space Freed: **~250 MB**
- Recent files: **Kept** (not deleted)

---

## Verification

### Automated Test Suite

```bash
# Run comprehensive tests (45 tests covering all features)
./scripts/comprehensive_test.sh

# Expected output:
# ✅ 45/45 TESTS PASSED
# ⏱️  Duration: 45 seconds
```

### Manual Verification

```bash
# 1. Check services are running
docker-compose ps

# All services should be "Up" and "healthy"

# 2. Check metrics
curl -s http://localhost:9090/metrics | grep storagesage

# Should show:
# storagesage_files_deleted_total
# storagesage_bytes_freed_total
# storagesage_cleanup_duration_seconds

# 3. Check database
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --stats

# Should show deletion statistics

# 4. Check API health
curl -sk https://localhost:8443/api/v1/health | jq

# Should return: {"status": "healthy"}
```

### Verify Real Deletions

```bash
# Run the real deletion test
./test_real_deletion.sh

# This will:
# 1. Create a test file (10 days old)
# 2. Trigger cleanup
# 3. Verify file was ACTUALLY deleted
# 4. Show metrics increase
```

---

## Adding Custom Paths

### Method 1: Edit Configuration File

```bash
# 1. Stop services
docker-compose down

# 2. Edit config
nano web/config/config.yaml

# 3. Add your path to scan_paths
scan_paths:
    - /test-workspace
    - /tmp/storage-sage-test-workspace
    - /your/custom/path          # ← Add here

# 4. Add path-specific rules (optional)
paths:
    - path: /your/custom/path
      age_off_days: 7
      min_free_percent: 5
      max_free_percent: 90
      target_free_percent: 80
      priority: 1
      stack_threshold: 95
      stack_age_days: 14

# 5. Update docker-compose.yml to mount the path
nano docker-compose.yml

# Add under storage-sage-daemon volumes:
volumes:
    - ./web/config:/etc/storage-sage:ro
    - storage-sage-data:/var/lib/storage-sage
    - /tmp/storage-sage-test-workspace:/test-workspace:z
    - /your/custom/path:/your/custom/path:z    # ← Add here

# 6. Restart services
docker-compose up -d

# 7. Verify new path is scanned
docker-compose logs storage-sage-daemon | grep "Scanning paths"
```

### Method 2: Using API (Runtime Configuration)

```bash
# Get auth token
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' | jq -r '.token')

# Get current config
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/config | jq

# Update config (requires restart)
# Note: This updates the running config but requires daemon restart
```

### Important Notes for Custom Paths

1. **Permissions**: Ensure the daemon has read/write access
   ```bash
   # Make directory accessible
   chmod 755 /your/custom/path

   # Or change ownership
   sudo chown -R 1000:1000 /your/custom/path
   ```

2. **Volume Mounts**: Must mount into Docker container
   ```yaml
   volumes:
       - /host/path:/container/path:z
   ```

3. **SELinux**: Add `:z` suffix on SELinux systems (Fedora, RHEL, CentOS)

4. **Test First**: Create a test directory first to verify permissions

---

## Monitoring & Observability

### Prometheus Metrics

Access metrics at: `http://localhost:9090/metrics`

**Key Metrics:**
```
# Files deleted
storagesage_files_deleted_total

# Space freed (bytes)
storagesage_bytes_freed_total

# Cleanup duration (seconds)
storagesage_cleanup_duration_seconds

# Cleanup mode (AGE=0, DISK_USAGE=1, STACK=2)
storagesage_cleanup_last_mode

# Error count
storagesage_cleanup_errors_total
```

### Loki Logs

Access logs via Grafana or API:

```bash
# Query recent logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="storage-sage"}' | jq
```

### Grafana Dashboards

```bash
# Start with Grafana
docker-compose --profile grafana up -d

# Access Grafana
open http://localhost:3000

# Default credentials:
# Username: admin
# Password: admin
```

**Import Dashboard:**
1. Go to Dashboards → Import
2. Upload `grafana/dashboards/storage-sage.json`
3. View real-time metrics and logs

### Database Queries

```bash
# Total deletions
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --stats

# Recent deletions
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --recent 20

# Deletions by mode
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --mode AGE

# Date range
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --since "2024-01-01" \
  --until "2024-12-31"
```

---

## Security

### TLS/HTTPS

**Default**: Self-signed certificate (for testing)

**Production**: Use your own certificate

```bash
# Generate certificate
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout web/backend/server.key \
  -out web/backend/server.crt \
  -days 365 \
  -subj "/CN=yourdomain.com"

# Update docker-compose.yml
volumes:
    - ./web/backend/server.crt:/etc/ssl/certs/server.crt:ro
    - ./web/backend/server.key:/etc/ssl/private/server.key:ro

# Restart
docker-compose restart storage-sage-backend
```

### Authentication

**Change Default Password:**

```bash
# Method 1: Environment variable
echo "JWT_SECRET=your-secure-random-secret-here" > .env
docker-compose up -d

# Method 2: Direct in docker-compose.yml
environment:
    - JWT_SECRET=your-secure-random-secret-here
```

**Create New User:**

Currently single user (admin). For multi-user support, modify `web/backend/auth.go`

### Non-Root Container

StorageSage runs as non-root user (UID 1000) by default:

```bash
# Verify
docker exec storage-sage-daemon id
# Output: uid=1000(storage-sage) gid=1000(storage-sage)
```

### Security Headers

Enabled by default:
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `Strict-Transport-Security: max-age=31536000`

Verify:
```bash
curl -skI https://localhost:8443/api/v1/health | grep -E "X-|Strict"
```

---

## Troubleshooting

### Issue: Daemon not starting

**Check logs:**
```bash
docker-compose logs storage-sage-daemon
```

**Common causes:**
1. **Port already in use**: Change ports in docker-compose.yml
2. **Config error**: Validate YAML syntax
   ```bash
   yamllint web/config/config.yaml
   ```
3. **Permission denied**: Check volume mount permissions

### Issue: No files being deleted

**Checklist:**
```bash
# 1. Check age_off_days is not 0
grep age_off_days web/config/config.yaml
# Should be > 0 (e.g., 7)

# 2. Verify paths are scanned
docker-compose logs storage-sage-daemon | grep "Scanning"

# 3. Check cleanup interval
curl -s http://localhost:9090/metrics | grep cleanup_duration
# Should show recent cleanups

# 4. Verify files are old enough
find /tmp/storage-sage-test-workspace -type f -mtime +7
# Should show files older than 7 days

# 5. Check for errors
curl -s http://localhost:9090/metrics | grep cleanup_errors
```

### Issue: "DRY-RUN MODE" badge showing

**This is a UI bug** - files are likely being deleted. Verify:

```bash
# Run real deletion test
./test_real_deletion.sh

# If files ARE being deleted, ignore the badge
# To fix UI: restart services
docker-compose restart
```

### Issue: Permission denied errors

**Solution:**
```bash
# Option 1: Fix permissions
chmod -R 755 /your/path
chown -R 1000:1000 /your/path

# Option 2: Run as root (not recommended)
docker-compose exec -u root storage-sage-daemon bash

# Option 3: Remove path from scan_paths
# Edit web/config/config.yaml and remove the problematic path
```

### Issue: High memory usage

**Check:**
```bash
docker stats storage-sage-daemon --no-stream

# Expected: 10-50 MB
# If higher:
# 1. Reduce scan frequency (increase interval_minutes)
# 2. Enable cache: use_cache: true
# 3. Reduce parallel_scans
```

### Issue: Database locked

```bash
# Check for multiple processes
docker exec storage-sage-daemon ps aux | grep storage-sage

# Should only be one process
# If multiple, restart:
docker-compose restart storage-sage-daemon
```

### Issue: Cannot connect to API

```bash
# 1. Check backend is running
docker-compose ps storage-sage-backend

# 2. Check port binding
netstat -tlnp | grep 8443

# 3. Check firewall
sudo iptables -L | grep 8443

# 4. Test connectivity
curl -sk https://localhost:8443/api/v1/health
```

### Issue: Metrics not showing

```bash
# 1. Check Prometheus is running
docker-compose ps prometheus

# 2. Test metrics endpoint
curl -s http://localhost:9090/metrics | head -20

# 3. Check Prometheus targets
open http://localhost:9090/targets

# All targets should be "UP"
```

---

## Production Deployment

### Recommended Configuration

```yaml
# web/config/config.yaml (production)
scan_paths:
    - /var/log
    - /data/backups
    - /tmp

min_free_percent: 15              # More aggressive
age_off_days: 30                  # Longer retention
interval_minutes: 15              # Less frequent

paths:
    - path: /var/log
      age_off_days: 30
      priority: 3                 # Keep longer

    - path: /tmp
      age_off_days: 7
      priority: 1                 # Delete first

resource_limits:
    max_cpu_percent: 5            # Lower limit

scan_optimizations:
    use_fast_scan: true           # Better performance
    use_cache: true               # Cache results
    cache_ttl_minutes: 10
```

### Production Checklist

- [ ] **Change default password**
- [ ] **Use real TLS certificates** (not self-signed)
- [ ] **Set custom JWT_SECRET**
- [ ] **Configure backup for SQLite database**
- [ ] **Set up log rotation**
- [ ] **Configure monitoring alerts** (Prometheus Alertmanager)
- [ ] **Test disaster recovery**
- [ ] **Document path configurations**
- [ ] **Set up automated backups of config.yaml**
- [ ] **Configure resource limits** (CPU, memory)
- [ ] **Enable Grafana for dashboards**
- [ ] **Set up external log shipping** (Loki to S3/etc)

### Backup Database

```bash
# Automated backup script
cat > backup_database.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/storage-sage"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup database
docker exec storage-sage-daemon sqlite3 \
  /var/lib/storage-sage/deletions.db \
  ".backup /tmp/backup.db"

docker cp storage-sage-daemon:/tmp/backup.db \
  "$BACKUP_DIR/deletions_${DATE}.db"

# Keep only last 30 days
find "$BACKUP_DIR" -name "deletions_*.db" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR/deletions_${DATE}.db"
EOF

chmod +x backup_database.sh

# Add to crontab
crontab -e
# Add: 0 2 * * * /path/to/backup_database.sh
```

### Resource Limits (Docker)

```yaml
# docker-compose.yml (production)
services:
  storage-sage-daemon:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.1'
          memory: 128M
```

### Health Checks

```yaml
# docker-compose.yml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:9090/metrics"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### Alerting (Prometheus)

```yaml
# prometheus/alerts.yml
groups:
  - name: storage-sage
    interval: 30s
    rules:
      - alert: StorageSageDown
        expr: up{job="storage-sage"} == 0
        for: 5m
        annotations:
          summary: "StorageSage daemon is down"

      - alert: HighErrorRate
        expr: rate(storagesage_cleanup_errors_total[5m]) > 0.1
        for: 5m
        annotations:
          summary: "StorageSage error rate is high"

      - alert: DiskStillFull
        expr: storagesage_cleanup_last_mode == 2
        for: 30m
        annotations:
          summary: "Disk in STACK mode for 30+ minutes"
```

---

## Advanced Topics

### Custom Cleanup Logic

Edit `internal/cleanup/cleanup.go` to add custom logic:

```go
// Example: Skip files with .important extension
func shouldSkipFile(path string) bool {
    if strings.HasSuffix(path, ".important") {
        return true
    }
    return false
}
```

### Integration with External Systems

**Webhook on deletion:**

```go
// In internal/cleanup/cleanup.go
func notifyWebhook(path string, size int64) {
    payload := map[string]interface{}{
        "path": path,
        "size": size,
        "timestamp": time.Now(),
    }

    // POST to webhook URL
    http.Post("https://your-webhook.com/notify", "application/json", ...)
}
```

### Multiple Instances

Run multiple StorageSage instances for different storage systems:

```bash
# Instance 1: Production logs
docker-compose -f docker-compose.prod.yml up -d

# Instance 2: Development logs
docker-compose -f docker-compose.dev.yml up -d

# Use different ports and databases
```

---

## Support & Resources

### Documentation
- **GitHub**: https://github.com/yourusername/storage-sage
- **Issues**: https://github.com/yourusername/storage-sage/issues
- **Wiki**: https://github.com/yourusername/storage-sage/wiki

### Scripts Reference
- `scripts/start.sh` - Start all services
- `scripts/comprehensive_test.sh` - Run full test suite
- `scripts/create_test_files.sh` - Generate test files
- `test_real_deletion.sh` - Verify real deletions
- `VERIFY_ALL_CLAIMS.sh` - Prove all features work

### Getting Help

1. **Check logs**: `docker-compose logs -f`
2. **Run diagnostics**: `./scripts/comprehensive_test.sh`
3. **Search issues**: GitHub Issues
4. **Ask for help**: Open a new issue with logs

---

## Quick Reference

### Essential Commands

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# Restart
docker-compose restart

# Logs
docker-compose logs -f storage-sage-daemon

# Status
docker-compose ps

# Update
git pull
docker-compose pull
docker-compose up -d

# Backup database
docker cp storage-sage-daemon:/var/lib/storage-sage/deletions.db ./backup.db

# Shell access
docker exec -it storage-sage-daemon sh
```

### API Endpoints

```bash
# Health check
GET https://localhost:8443/api/v1/health

# Login
POST https://localhost:8443/api/v1/auth/login
Body: {"username": "admin", "password": "changeme"}

# Get config
GET https://localhost:8443/api/v1/config
Header: Authorization: Bearer <token>

# Trigger cleanup
POST https://localhost:8443/api/v1/cleanup/trigger
Header: Authorization: Bearer <token>

# Deletion log
GET https://localhost:8443/api/v1/deletions/log?limit=20
Header: Authorization: Bearer <token>

# Statistics
GET https://localhost:8443/api/v1/deletions/stats
Header: Authorization: Bearer <token>
```

---

## Next Steps

1. ✅ **Install** - Follow Quick Start
2. ✅ **Configure** - Edit config.yaml for your paths
3. ✅ **Test** - Run create_test_files.sh and verify
4. ✅ **Monitor** - Set up Grafana dashboards
5. ✅ **Secure** - Change passwords and certificates
6. ✅ **Automate** - Set up backups and alerts

**You're all set!** StorageSage is now monitoring and managing your storage automatically.

For questions or issues, check the Troubleshooting section or open a GitHub issue.
