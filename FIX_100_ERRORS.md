# Fixing the 100 Errors Issue

## Problem
Dashboard shows **Errors: 100** - the daemon is encountering errors during cleanup cycles.

## Common Causes & Solutions

### 1. **Scan Path Doesn't Exist**

The most common cause - the daemon is trying to scan paths that don't exist.

**Check which paths are configured:**
```bash
cat web/config/config.yaml | grep -A 5 "scan_paths:"
```

**Your current config scans:**
- `/var/log`
- `/test-workspace`
- `/tmp/storage-sage-test-workspace`

**Fix: Create missing directories**
```bash
# On the HOST machine:
sudo mkdir -p /var/log
mkdir -p /tmp/storage-sage-test-workspace/var/log

# Check if they exist:
ls -la /var/log
ls -la /tmp/storage-sage-test-workspace
```

---

### 2. **Permission Denied**

The daemon doesn't have permission to read/delete files in the scan paths.

**Check logs for permission errors:**
```bash
docker logs storage-sage-daemon 2>&1 | grep -i "permission denied"
```

**Fix: Adjust permissions**
```bash
# Make test directory writable
chmod -R 755 /tmp/storage-sage-test-workspace

# Or set ownership (if running as specific user)
sudo chown -R 1000:1000 /tmp/storage-sage-test-workspace
```

---

### 3. **Path Not Mounted in Container**

The scan path exists on host but isn't mounted into the container.

**Check what's mounted:**
```bash
docker inspect storage-sage-daemon --format='{{range .Mounts}}{{.Source}} → {{.Destination}}{{println}}{{end}}'
```

**Expected mounts should include:**
- `/tmp/storage-sage-test-workspace` → `/tmp/storage-sage-test-workspace` (or similar)

**Fix: Check docker-compose.yml volumes**
```bash
cat docker-compose.yml | grep -A 10 "storage-sage-daemon:" | grep -A 10 "volumes:"
```

Should have:
```yaml
volumes:
  - /tmp/storage-sage-test-workspace:/test-workspace:z
  # OR
  - /tmp/storage-sage-test-workspace:/tmp/storage-sage-test-workspace:z
```

---

### 4. **NFS Timeout**

If scanning NFS mounts, timeouts can cause errors.

**Check config:**
```bash
cat web/config/config.yaml | grep nfs_timeout
```

**Fix: Increase timeout**
```yaml
nfs_timeout_seconds: 10  # Increase from 5 to 10
```

---

### 5. **Database Errors**

SQLite database might have permission issues.

**Check database:**
```bash
docker exec storage-sage-daemon ls -la /var/lib/storage-sage/
docker exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "SELECT COUNT(*) FROM deletions;"
```

**Fix: Reset database if corrupted**
```bash
# Backup first
docker exec storage-sage-daemon cp /var/lib/storage-sage/deletions.db /var/lib/storage-sage/deletions.db.backup

# Remove and let it recreate
docker exec storage-sage-daemon rm /var/lib/storage-sage/deletions.db
docker-compose restart storage-sage-daemon
```

---

## Diagnostic Steps

### Step 1: Check Daemon Logs
```bash
# Look for ERROR lines
docker logs storage-sage-daemon 2>&1 | grep -i error | tail -20

# Look for specific error patterns
docker logs storage-sage-daemon 2>&1 | grep -E "(permission|not found|no such|timeout)" | tail -20
```

### Step 2: Check Metrics for Error Details
```bash
# Get error count
curl -s http://localhost:9090/metrics | grep storagesage_errors_total

# Check if errors have labels with more info
curl -s http://localhost:9090/metrics | grep -A 5 storagesage_errors
```

### Step 3: Verify Scan Paths
```bash
# From container perspective
docker exec storage-sage-daemon ls -la /var/log
docker exec storage-sage-daemon ls -la /test-workspace
docker exec storage-sage-daemon ls -la /tmp/storage-sage-test-workspace

# Check if paths are readable
docker exec storage-sage-daemon sh -c 'for path in /var/log /test-workspace /tmp/storage-sage-test-workspace; do echo "Testing: $path"; ls "$path" >/dev/null 2>&1 && echo "  OK" || echo "  ERROR"; done'
```

### Step 4: Test Cleanup Manually
```bash
# Trigger cleanup and watch logs
docker logs -f storage-sage-daemon &
LOG_PID=$!

# In another terminal, trigger cleanup
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# Watch the logs for errors
# Then kill the log tail
kill $LOG_PID
```

---

## Quick Fix (Most Likely Solution)

The 100 errors are probably from trying to scan `/var/log` which either:
1. Doesn't exist in the container
2. Has permission issues
3. Isn't mounted

**Solution: Focus on the test workspace that IS properly mounted**

### Option A: Remove problematic paths from config

Edit `web/config/config.yaml`:
```yaml
scan_paths:
    # - /var/log  # COMMENT OUT - causing errors
    # - /test-workspace  # COMMENT OUT if not mounted
    - /tmp/storage-sage-test-workspace  # Keep this one
```

Then restart:
```bash
docker-compose restart storage-sage-daemon
```

### Option B: Create and mount all paths properly

1. Create test workspace:
```bash
mkdir -p /tmp/storage-sage-test-workspace/var/log
chmod -R 755 /tmp/storage-sage-test-workspace
```

2. Verify mount in docker-compose.yml:
```yaml
volumes:
  - /tmp/storage-sage-test-workspace:/test-workspace:z
```

3. Restart:
```bash
docker-compose restart storage-sage-daemon
```

---

## Verify Fix Worked

After applying the fix:

```bash
# Wait 30 seconds for a cleanup cycle
sleep 30

# Check errors - should be 0 or not increasing
curl -s http://localhost:9090/metrics | grep storagesage_errors_total

# Check logs for recent errors
docker logs storage-sage-daemon --since 1m 2>&1 | grep -i error
```

**Expected result:**
- Errors counter stops increasing
- No new ERROR lines in logs
- Dashboard shows Errors: 100 (old errors, but not increasing)

To **reset the error counter**, restart the daemon:
```bash
docker-compose restart storage-sage-daemon
```

Then errors should be 0 if the issue is fixed.

---

## Create Test Files and See Deletions

Once errors are fixed:

```bash
# 1. Create test files in the working directory
./scripts/create_test_files.sh

# 2. Trigger cleanup
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# 3. Wait and check
sleep 5
curl -s http://localhost:9090/metrics | grep -E "(files_deleted|bytes_freed|errors)"
```

**You should see:**
- Files Deleted: > 0
- Bytes Freed: > 0
- Errors: 0 (or not increasing)

---

## Summary

The 100 errors are likely from:
- ❌ Scanning `/var/log` which doesn't exist or has no permissions
- ❌ Scanning `/test-workspace` which isn't mounted

**Quick fix:**
```bash
# Edit config to only scan the test workspace
nano web/config/config.yaml
# Comment out /var/log and /test-workspace
# Keep only /tmp/storage-sage-test-workspace

# Restart
docker-compose restart storage-sage-daemon

# Create test files
./scripts/create_test_files.sh

# Watch it work!
```
