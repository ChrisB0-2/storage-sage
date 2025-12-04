# Permission Fix - Database Directory Ownership Issue

## Root Cause Analysis

### Problem Discovery
Diagnostic output revealed:
```
[4/8] Checking if database directory exists...
  drwxr-xr-x    2 root     root     6 Nov 18 00:33 /var/lib/storage-sage
                  ^^^^     ^^^^
                  Should be: storagesage storagesage
```

### Why This Happens
Docker volumes mounted over directories reset ownership to `root:root` by default. When the container starts:

```
1. Dockerfile creates /var/lib/storage-sage with ownership storagesage:storagesage
2. Docker mounts volume storage-sage-db:/var/lib/storage-sage
3. Volume mount OVERWRITES directory ownership → becomes root:root
4. Daemon (running as UID 1000) cannot create database file
5. Query tool (running as UID 1000) cannot create database file
```

### Error Chain
```
storage-sage daemon starts (UID 1000)
  → Tries to create /var/lib/storage-sage/deletions.db
  → Permission denied (directory owned by root:root)
  → Logs error: "unable to open database file"
  → Falls back to file-only logging

storage-sage-query runs (UID 1000)
  → Tries to open /var/lib/storage-sage/deletions.db
  → Permission denied (directory owned by root:root)
  → Exits with error code 1
  → Test Q7 fails
```

## Solutions Implemented

### Solution 1: Immediate Fix (No Rebuild Required)

Execute once to fix existing container:

```bash
# Fix ownership in running container
docker exec --user root storage-sage-daemon \
  chown -R storagesage:storagesage /var/lib/storage-sage

# Restart daemon to initialize database
docker compose restart storage-sage-daemon

# Wait for initialization
sleep 5

# Verify fix
docker exec storage-sage-daemon ls -ld /var/lib/storage-sage
# Expected: drwxr-xr-x 2 storagesage storagesage ...

# Test database creation
docker exec storage-sage-daemon \
  storage-sage-query --db /var/lib/storage-sage/deletions.db --stats

# Re-run diagnostics
./scripts/diagnose_q7.sh
```

**Pros:** Fast, no rebuild needed
**Cons:** Must be run every time volume is recreated

### Solution 2: Permanent Fix with Entrypoint (Recommended)

Modified Dockerfile to use entrypoint script that fixes permissions on every startup.

#### Files Modified

**1. Created: `cmd/storage-sage/entrypoint.sh`**
- Runs as root on startup
- Fixes ownership of volume-mounted directories
- Switches to storagesage user
- Executes daemon

**2. Modified: `cmd/storage-sage/Dockerfile`**
- Added `su-exec` package (lightweight user switching)
- Added `/var/lib/storage-sage` to directory creation
- Copied entrypoint script
- Changed ENTRYPOINT to use entrypoint script
- Removed `USER storagesage` directive (entrypoint handles this)

#### How Entrypoint Works

```bash
Container starts → Entrypoint runs as root
  ↓
Check ownership of /var/lib/storage-sage
  ↓
Fix ownership: chown storagesage:storagesage /var/lib/storage-sage
  ↓
Switch to storagesage user with su-exec
  ↓
Execute daemon as storagesage
```

#### Deployment with Permanent Fix

```bash
# Rebuild daemon image with entrypoint
docker compose build --no-cache storage-sage-daemon

# Stop and remove old container
docker compose stop storage-sage-daemon
docker compose rm -f storage-sage-daemon

# Start with new image
docker compose up -d storage-sage-daemon

# Verify entrypoint ran
docker logs storage-sage-daemon | head -10
# Should show:
# Storage-Sage Daemon Entrypoint
# Running as root - fixing permissions...
# Fixing ownership: /var/lib/storage-sage
# Permissions fixed - switching to storagesage user

# Verify ownership
docker exec storage-sage-daemon ls -ld /var/lib/storage-sage
# Expected: drwxr-xr-x 2 storagesage storagesage ...

# Test database initialization
sleep 5
docker exec storage-sage-daemon \
  storage-sage-query --db /var/lib/storage-sage/deletions.db --stats

# Run full diagnostic
./scripts/diagnose_q7.sh

# Run test suite
./scripts/comprehensive_test.sh
```

## Comparison Matrix

| Aspect | Immediate Fix | Permanent Fix (Entrypoint) |
|--------|---------------|----------------------------|
| **Time to Deploy** | 10 seconds | 5 minutes (rebuild) |
| **Requires Rebuild** | No | Yes |
| **Persists After Volume Recreate** | No | Yes |
| **Runs on Every Start** | No | Yes (automatic) |
| **Production Ready** | No (temporary) | Yes (recommended) |
| **Image Size Impact** | None | +20KB (su-exec) |
| **Security Impact** | None | None (still runs as non-root) |

## Verification Steps

### After Immediate Fix
```bash
# 1. Check directory ownership
docker exec storage-sage-daemon ls -ld /var/lib/storage-sage
# Expect: drwxr-xr-x ... storagesage storagesage

# 2. Verify daemon can create database
docker logs storage-sage-daemon | grep -i database
# Should NOT show permission errors

# 3. Test query tool
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db --stats
# Should show "Total Records: 0" or "Database Statistics"

# 4. Run diagnostic
./scripts/diagnose_q7.sh
# [7/8] should show: ✓ Query executed successfully
```

### After Permanent Fix
```bash
# 1. Check entrypoint execution
docker logs storage-sage-daemon | head -15
# Should show entrypoint messages

# 2. Verify process running as correct user
docker exec storage-sage-daemon ps aux | grep storage-sage
# UID should be 1000 (storagesage)

# 3. Test volume recreation resilience
docker compose down -v  # Removes volumes
docker compose up -d
sleep 10
docker exec storage-sage-daemon ls -ld /var/lib/storage-sage
# Should STILL be: storagesage storagesage (entrypoint fixed it)

# 4. Run full test suite
./scripts/comprehensive_test.sh
```

## Expected Test Results

### Before Fix
```
================================
  DATABASE QUERY CLI FEATURES
================================
  [Pre-check] Verifying storage-sage-query binary... ✓
[Q7] Database statistics query... ❌ FAIL
  Error output:
    Error opening database: unable to open database file: no such file or directory
[Q1] Recent deletions query... ❌ FAIL
```

### After Fix
```
================================
  DATABASE QUERY CLI FEATURES
================================
  [Pre-check] Verifying storage-sage-query binary... ✓
[Q7] Database statistics query... ✅ PASS
[Q1] Recent deletions query... ✅ PASS
```

## Edge Cases Handled

| Edge Case | Behavior | Handled By |
|-----------|----------|------------|
| Volume already has correct ownership | Entrypoint no-op (fast) | chown is idempotent |
| Volume recreated with docker compose down -v | Entrypoint fixes on next start | Automatic |
| Manual volume mount with wrong ownership | Entrypoint fixes on start | Automatic |
| Container restarted | Entrypoint re-runs, fixes if needed | Automatic |
| Running as non-root initially | Entrypoint detects, skips permission fix | User check |

## Security Analysis

### Entrypoint Security
```
✅ Container starts as root (required for chown)
✅ Entrypoint fixes permissions ONLY for known directories
✅ Immediately switches to storagesage user (UID 1000)
✅ Daemon runs as non-root throughout execution
✅ No privilege escalation after startup
✅ Uses su-exec (lightweight, secure alternative to gosu)
```

### Attack Surface
- **Before:** None (daemon couldn't write to database)
- **After:** None (daemon writes to owned directory only)
- **Risk:** None (standard container permission model)

## Rollback Procedure

### Rollback Permanent Fix
```bash
# Revert Dockerfile changes
git diff cmd/storage-sage/Dockerfile
git checkout HEAD -- cmd/storage-sage/Dockerfile
git checkout HEAD -- cmd/storage-sage/entrypoint.sh

# Rebuild
docker compose build --no-cache storage-sage-daemon
docker compose up -d storage-sage-daemon

# Apply immediate fix instead
docker exec --user root storage-sage-daemon \
  chown -R storagesage:storagesage /var/lib/storage-sage
docker compose restart storage-sage-daemon
```

## Related Issues

### Other Components with Same Issue
Check if backend or other services have similar permission problems:

```bash
# Check backend database access
docker exec storage-sage-backend ls -ld /var/lib/storage-sage
# Should be readable by backend user

# Check log directories
docker exec storage-sage-daemon ls -ld /var/log/storage-sage
# Should be owned by storagesage
```

## Future Improvements

1. **InitContainer Pattern**
   - Separate init container that fixes permissions
   - Main container runs as pure non-root
   - More Kubernetes-friendly

2. **UID Mapping**
   - Use Docker user namespace remapping
   - Volume ownership automatically correct
   - Requires Docker daemon configuration

3. **Named Volumes with Ownership**
   - Create volumes with pre-set ownership
   - Use docker volume create with options
   - Platform-specific

## Documentation Updates

Files requiring updates:
- [x] `FIX_PERMISSIONS.md` (this file)
- [x] `cmd/storage-sage/Dockerfile` (entrypoint added)
- [x] `cmd/storage-sage/entrypoint.sh` (new file)
- [ ] `DEPLOYMENT_MANUAL.md` (add permission troubleshooting)
- [ ] `README.docker.md` (mention entrypoint)
- [ ] `docker-compose.yml` (no changes needed)

## Summary

**Root Cause:** Docker volume mount overwrites directory ownership to root:root
**Immediate Fix:** One-time chown command (temporary)
**Permanent Fix:** Entrypoint script that fixes permissions on every startup (recommended)
**Impact:** Zero security regression, enables database functionality
**Status:** Production-ready with permanent fix

**Recommendation:** Deploy permanent fix to avoid manual intervention on volume recreation.
