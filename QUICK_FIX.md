# 🔥 QUICK FIX: Why No Files Are Being Deleted

## The Problem

Looking at your config file, I found the issue:

```yaml
age_off_days: 0  # ← THIS IS THE PROBLEM!
```

**When `age_off_days: 0`, the daemon won't delete ANY files in AGE mode!**

## The Solution

You have TWO options:

---

### Option 1: Edit the Config File (Recommended)

```bash
# Edit the config
nano web/config/config.yaml

# Change line 7 from:
age_off_days: 0

# To:
age_off_days: 7    # Delete files older than 7 days

# Save and restart daemon
docker-compose restart storage-sage-daemon
```

---

### Option 2: Use Path-Specific Config (Already Working!)

Your config DOES have path-specific settings that should work:

```yaml
paths:
    - path: /test-workspace
      age_off_days: 7      # ← This should work!
    - path: /tmp/storage-sage-test-workspace
      age_off_days: 7      # ← This should work too!
```

So files in `/test-workspace` or `/tmp/storage-sage-test-workspace` should be deleted if older than 7 days.

---

## Immediate Test

Let's test if it's working with the path-specific config:

```bash
# 1. Create old test files in the right location
mkdir -p /tmp/storage-sage-test-workspace/var/log

# Create files 10 days old
for i in {1..10}; do
    echo "Test file $i" > /tmp/storage-sage-test-workspace/var/log/test_$i.txt
    touch -t $(date -d '10 days ago' +%Y%m%d%H%M) /tmp/storage-sage-test-workspace/var/log/test_$i.txt
done

# 2. Verify files were created
ls -lh /tmp/storage-sage-test-workspace/var/log/test_*.txt

# 3. Check how old they are
find /tmp/storage-sage-test-workspace/var/log -name "test_*.txt" -mtime +7

# 4. Trigger cleanup
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# 5. Wait 5 seconds
sleep 5

# 6. Check if files were deleted
ls -lh /tmp/storage-sage-test-workspace/var/log/test_*.txt 2>&1 || echo "Files deleted!"

# 7. Check metrics
curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total
```

---

## Why This Happened

Your configuration has:

1. **Global default:** `age_off_days: 0` (no deletions)
2. **Path-specific overrides:** `age_off_days: 7` (for specific paths)

The daemon scans ALL paths in `scan_paths`:
- `/var/log` → uses global age_off_days: 0 → **no deletions**
- `/test-workspace` → uses path-specific age_off_days: 7 → **should work**
- `/tmp/storage-sage-test-workspace` → uses path-specific age_off_days: 7 → **should work**

But if the daemon is scanning `/var/log` and finding no files (because age_off_days: 0), it reports 0 deletions.

---

## Recommended Config Fix

Edit `web/config/config.yaml`:

```yaml
scan_paths:
    - /var/log
    - /test-workspace
    - /tmp/storage-sage-test-workspace

min_free_percent: 10
age_off_days: 7           # ← CHANGE FROM 0 TO 7
interval_minutes: 1

database_path: /var/lib/storage-sage/deletions.db

paths:
    - path: /test-workspace
      age_off_days: 7
      min_free_percent: 5
      max_free_percent: 90
      target_free_percent: 80
      priority: 1
      stack_threshold: 95
      stack_age_days: 14

    - path: /tmp/storage-sage-test-workspace
      age_off_days: 7
      min_free_percent: 5
      max_free_percent: 90
      target_free_percent: 80
      priority: 1
      stack_threshold: 95
      stack_age_days: 14

prometheus:
    port: 9090

logging:
    rotation_days: 30

resource_limits:
    max_cpu_percent: 10

cleanup_options:
    recursive: true
    delete_dirs: false

nfs_timeout_seconds: 5
```

**Then restart:**
```bash
docker-compose restart storage-sage-daemon
# Or
docker compose restart storage-sage-daemon
```

---

## Complete Working Example

```bash
# 1. Fix the config
sed -i 's/^age_off_days: 0/age_off_days: 7/' web/config/config.yaml

# 2. Restart daemon
docker-compose restart storage-sage-daemon

# 3. Create test files (use the script)
./scripts/create_test_files.sh

# 4. Wait for automatic cleanup (runs every 1 minute)
# OR trigger manually:
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# 5. Watch it work!
watch -n 2 'curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total'
```

---

## Expected Result

After the fix, you should see:

```bash
$ curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total
storagesage_files_deleted_total 24

$ curl -s http://localhost:9090/metrics | grep storagesage_bytes_freed_total
storagesage_bytes_freed_total 52428800
```

And in the Web UI:
- **Files Deleted:** 24
- **Space Freed:** 50.00 MB
- **Cleanup Cycles:** 32
- **Errors:** 0

---

## TL;DR

**THE FIX:**
```bash
# Change age_off_days from 0 to 7
sed -i 's/^age_off_days: 0/age_off_days: 7/' web/config/config.yaml

# Restart
docker-compose restart storage-sage-daemon

# Create test files
./scripts/create_test_files.sh

# Watch it work
# (automatic cleanup runs every 1 minute, or trigger manually)
```

That's it! 🎉
