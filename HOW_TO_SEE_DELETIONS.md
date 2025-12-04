# How to See Actual File Deletions in StorageSage

## 🔍 Problem: Dashboard Shows "DRY-RUN MODE"

You're seeing **0 files deleted** because the daemon is running in **dry-run mode**, which identifies files for deletion but doesn't actually delete them.

---

## ✅ Solution: Enable Real Deletions

### Method 1: Use the Enable Script (Recommended)

I've created a script that will restart the daemon in real deletion mode:

```bash
./enable_real_deletion.sh
```

This script will:
1. Stop the current daemon
2. Verify the configuration
3. Rebuild the daemon container
4. Restart without --dry-run flag
5. Verify it's running

### Method 2: Manual Steps

If you prefer to do it manually:

```bash
# 1. Check current Dockerfile CMD
cat cmd/storage-sage/Dockerfile | grep CMD
# Should show: CMD ["/app/storage-sage", "--config", "/etc/storage-sage/config.yaml"]
# (No --dry-run flag = good!)

# 2. Rebuild and restart daemon
docker-compose build --no-cache storage-sage-daemon
docker-compose up -d storage-sage-daemon

# 3. Verify it's running
docker ps | grep storage-sage-daemon

# 4. Check logs to confirm no dry-run
docker logs storage-sage-daemon --tail 20
```

---

## 🎬 Demonstration: See Deletions in Action

### Step 1: Create Test Files

Use the script I created:

```bash
./scripts/create_test_files.sh
```

This creates:
- **10 old files** (15 days old) → Should be DELETED
- **5 large files** (50MB, 20 days old) → Should be DELETED (high priority)
- **5 recent files** (1 day old) → Should be KEPT
- **9 mixed-age files** (8-30 days) → Some deleted based on threshold

### Step 2: Trigger Manual Cleanup

Get authenticated and trigger cleanup:

```bash
# Login to get token
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

# Trigger cleanup
curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# Or wait for automatic cleanup (runs every 1 minute based on config)
```

### Step 3: Watch the Dashboard

Open https://localhost:8443 in your browser and watch:
- **Files Deleted** counter incrementing
- **Space Freed** increasing
- **Cleanup Activity** graph showing deletions in real-time

### Step 4: Monitor Metrics

Watch metrics update live:

```bash
# Watch files deleted counter
watch -n 2 'curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total'

# Watch bytes freed
watch -n 2 'curl -s http://localhost:9090/metrics | grep storagesage_bytes_freed_total'

# Or view all metrics
curl -s http://localhost:9090/metrics | grep storagesage_
```

### Step 5: Verify Files Were Deleted

```bash
# List remaining files in test directory
ls -lh /tmp/storage-sage-test-workspace/var/log/test_*

# Recent files should still exist, old ones should be gone
```

### Step 6: Check Deletion Database

```bash
# View recent deletions
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --recent 20

# View statistics
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --stats

# Query specific details
docker exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT timestamp, path, size, mode, age_days FROM deletions ORDER BY timestamp DESC LIMIT 10;"
```

---

## 📊 What You Should See

### Before Cleanup:
```
Files Deleted: 0
Space Freed: 0 Bytes
Cleanup Cycles: 31
```

### After Cleanup:
```
Files Deleted: 24 (or similar - depends on age threshold)
Space Freed: 50+ MB
Cleanup Cycles: 32
```

### In the Metrics:
```bash
$ curl -s http://localhost:9090/metrics | grep deleted_total
storagesage_files_deleted_total 24
```

### In the Database:
```sql
$ docker exec storage-sage-daemon storage-sage-query --db /var/lib/storage-sage/deletions.db --stats

Database Statistics:
  Total Records: 24
  Total Size Freed: 52428800 bytes (50.00 MB)
  Oldest Record: 2025-11-30 23:45:12
  Newest Record: 2025-11-30 23:45:18
```

### In the Web UI:
- Dashboard shows updated counters
- Activity graph shows spike in deletions
- "DRY-RUN MODE" badge disappears
- Real-time metrics update

---

## 🔬 Understanding Cleanup Modes

StorageSage has 3 cleanup modes that you'll see in action:

### 1. AGE Mode (Normal Operations)
- **Trigger:** Disk usage is OK, routine cleanup
- **Action:** Delete files older than `age_off_days` (7 days in config)
- **You'll see:** Steady, predictable deletions

### 2. DISK-USAGE Mode
- **Trigger:** Free space < `max_free_percent` (90% in config)
- **Action:** Delete oldest files until reaching `target_free_percent` (80%)
- **You'll see:** More aggressive cleanup, prioritizing oldest files

### 3. STACK Mode (Emergency)
- **Trigger:** Free space < `stack_threshold` (95% in config)
- **Action:** Aggressively delete files older than `stack_age_days` (14 days)
- **You'll see:** Rapid deletion to prevent disk full

**Check current mode:**
```bash
curl -s http://localhost:9090/metrics | grep storagesage_cleanup_last_mode
```

---

## 🎯 Quick Start (Complete Workflow)

Run these commands in sequence:

```bash
# 1. Enable real deletions
./enable_real_deletion.sh

# 2. Create test files
./scripts/create_test_files.sh

# 3. Get auth token
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

# 4. Trigger cleanup
curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# 5. Wait a few seconds
sleep 5

# 6. Check results
echo "Files deleted:"
curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total

echo -e "\nRemaining files:"
ls -lh /tmp/storage-sage-test-workspace/var/log/test_* 2>/dev/null || echo "All test files deleted!"

# 7. View deletion log
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --recent 10
```

---

## 🐛 Troubleshooting

### Dashboard Still Shows DRY-RUN MODE

1. **Clear browser cache** - The frontend may be cached
2. **Hard refresh** - Ctrl+Shift+R (or Cmd+Shift+R on Mac)
3. **Check daemon logs:**
   ```bash
   docker logs storage-sage-daemon --tail 50
   ```
4. **Verify process arguments:**
   ```bash
   docker exec storage-sage-daemon ps aux | grep storage-sage
   ```

### No Files Being Deleted

1. **Check file ages match threshold:**
   ```bash
   # Config says age_off_days: 7
   # So files must be >7 days old
   ls -lh --time-style=long-iso /tmp/storage-sage-test-workspace/var/log/test_*
   ```

2. **Check cleanup is running:**
   ```bash
   docker logs storage-sage-daemon | grep -i "cleanup"
   ```

3. **Verify scan paths in config:**
   ```bash
   docker exec storage-sage-daemon cat /etc/storage-sage/config.yaml | grep -A 5 scan_paths
   ```

### Metrics Not Updating

1. **Check metrics endpoint:**
   ```bash
   curl -s http://localhost:9090/metrics | head -20
   ```

2. **Verify daemon is running:**
   ```bash
   docker ps | grep storage-sage-daemon
   ```

3. **Check backend can reach daemon:**
   ```bash
   docker logs storage-sage-backend | grep -i metrics
   ```

---

## 📝 Expected Timeline

When you run the full workflow:

| Time | Event | What You'll See |
|------|-------|----------------|
| T+0s | Create test files | 29 files created (60MB+) |
| T+5s | Trigger cleanup | API returns success message |
| T+6s | Cleanup starts | Daemon logs show "Starting cleanup cycle" |
| T+7-10s | Files deleted | Old files disappear from disk |
| T+10s | Metrics update | Counter shows files_deleted_total > 0 |
| T+11s | Database updated | Deletion records written to SQLite |
| T+12s | Dashboard updates | Web UI shows new counts |
| T+15s | Cleanup complete | Daemon logs show "Cleanup cycle finished" |

---

## 🎉 Success Indicators

You'll know deletions are working when you see:

✅ **Dashboard:** Files Deleted > 0, Space Freed > 0 MB
✅ **Metrics:** `storagesage_files_deleted_total` > 0
✅ **File System:** Old test files are gone
✅ **Database:** Records in deletions table
✅ **Logs:** "DELETED" messages in daemon logs
✅ **Web UI:** Activity graph showing spikes

---

## 🚀 Next Steps

Once deletions are working:

1. **Configure production paths** - Update `scan_paths` in config.yaml
2. **Adjust age thresholds** - Set appropriate `age_off_days` for each path
3. **Set up monitoring** - Configure Grafana dashboards and alerts
4. **Test emergency mode** - Simulate low disk space to see STACK mode
5. **Enable scheduling** - Let it run automatically every `interval_minutes`

---

## 📞 Need Help?

- **View logs:** `docker-compose logs -f storage-sage-daemon`
- **Check health:** `curl http://localhost:9090/health`
- **Run tests:** `./scripts/comprehensive_test.sh`
- **Full demo:** `./demo_all_features.sh`

Happy cleaning! 🧹✨
