# StorageSage Requirements Compliance Verification

## Overview

This document verifies that StorageSage meets all specified requirements for operation on RedHat Enterprise Linux 9/10 with support for NAS/NFS, fault tolerance, containerization, and comprehensive cleanup capabilities.

## Requirements Checklist

### ✅ 1. RedHat 9/10 Compatibility

**Requirement**: Software shall operate with RedHat9 with the option of using in RedHat10 in the near future.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- Go 1.23+ supports RHEL 9 and RHEL 10
- Uses standard Linux syscalls (`syscall.Statfs`) compatible with RHEL 9/10
- No RHEL-specific dependencies
- Systemd service file compatible with RHEL 9/10 systemd versions

**Implementation**:
- `internal/disk/disk.go` uses `syscall.Statfs` which is available on RHEL 9/10
- Standard Go runtime with no OS-specific code
- Service file uses standard systemd directives

---

### ✅ 2. Remove Logs and Large Files from Any Directory

**Requirement**: Software solution shall remove logs and large files from any directory within the RHEL-9 directory structure.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `internal/scan/scan.go` scans any configured directory
- `internal/cleanup/cleanup.go` removes files from any path
- Path validation ensures safety while allowing any directory

**Implementation**:
- Configurable `scan_paths` and `paths` in configuration
- Absolute path validation in `internal/config/config.go`
- File and directory scanning in `internal/scan/scan.go`

---

### ✅ 3. NAS/NFS Support

**Requirement**: Software solution shall remove files from a Network Attached Storage device (NAS) connected via the Network File System (NFS).

**Status**: ✅ **COMPLIANT**

**Evidence**:
- NFS stale file detection in `internal/disk/disk.go`
- Configurable NFS timeout in configuration
- Error handling for NFS-specific errors (EIO, ESTALE, ENXIO)

**Implementation**:
- `IsNFSStale()` function detects disconnected NFS mounts
- `nfs_timeout_seconds` configuration option
- Timeout-based detection prevents hanging on stale NFS
- Error handling in `internal/cleanup/cleanup.go` skips stale files

**Configuration Example**:
```yaml
nfs_timeout_seconds: 5  # 5 second timeout for NFS operations
```

---

### ✅ 4. Fault Tolerance via systemctl

**Requirement**: Software solution shall be fault tolerance trackable via systemctl.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- Systemd service file: `storage-sage.service`
- Restart policies configured
- Health tracking via systemd status

**Implementation**:
- `storage-sage.service` includes:
  - `Restart=on-failure`
  - `RestartSec=10`
  - `TimeoutStopSec=30`
- Service can be monitored via `systemctl status storage-sage`
- Faults are logged to systemd journal

**Usage**:
```bash
systemctl status storage-sage
systemctl restart storage-sage
journalctl -u storage-sage
```

---

### ✅ 5. BareMetal/Podman/RKE2 Support

**Requirement**: Software shall work within a BareMetal install or a Podman container, with the ability to run in RKE2 in the near future.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- Single binary deployment
- No hardcoded paths (configurable)
- Systemd service works on bare metal
- Podman container support via standard systemd
- RKE2 compatible (Kubernetes-ready)

**Implementation**:
- Binary can run standalone or in containers
- Configuration file path is configurable via `--config` flag
- Service file uses standard systemd directives
- No host-specific dependencies

---

### ✅ 6. Secure GUI Configuration

**Requirement**: Software shall be configurable via a secure GUI.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- Web backend with HTTPS (port 8443)
- JWT authentication in `web/backend/auth/`
- Role-based access control
- Configuration API endpoints

**Implementation**:
- `web/backend/api/routes.go` provides configuration endpoints
- JWT-based authentication
- HTTPS with TLS 1.3
- Permission-based access control

**Endpoints**:
- `GET /api/v1/config` - View configuration
- `PUT /api/v1/config` - Update configuration
- `POST /api/v1/auth/login` - Authentication

---

### ✅ 7. Age Off Date

**Requirement**: Age off date. Example: If files are older than 14 days remove.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `age_off_days` configuration option
- Per-path age configuration in `PathRule`
- Age-based scanning in `internal/scan/scan.go`

**Implementation**:
- Global `age_off_days` in config
- Per-path `age_off_days` in `PathRule`
- `scanPath()` function filters by modification time
- Oldest files deleted first

**Configuration Example**:
```yaml
age_off_days: 14
paths:
  - path: "/data/logs"
    age_off_days: 7
```

---

### ✅ 8. Directory % Free Threshold Cleanup

**Requirement**: Remove based on directory % free. Example: If /data is higher than 90% clean do to 80% starting with oldest file until the threshold is complete.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `MaxFreePercent` and `TargetFreePercent` in `PathRule`
- Disk usage calculation in `internal/disk/disk.go`
- Threshold-based cleanup in `internal/scan/scan.go`

**Implementation**:
- `GetDiskUsage()` calculates current usage
- `analyzePath()` determines if cleanup needed
- `scanPath()` selects files to free target space
- Files sorted by age (oldest first)

**Configuration Example**:
```yaml
paths:
  - path: "/data"
    max_free_percent: 90    # Trigger at 90% usage
    target_free_percent: 80  # Clean to 80% usage
```

---

### ✅ 9. Stacked Cleanup

**Requirement**: Stack the two above. Example: If directory is over 98% clean all files older than 14days.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `StackThreshold` and `StackAgeDays` in `PathRule`
- Stacked cleanup logic in `scanPath()`
- Combines disk usage and age thresholds

**Implementation**:
- When usage >= `stack_threshold`, uses `stack_age_days` cutoff
- More aggressive cleanup when disk is critically full
- Works in combination with regular age-based cleanup

**Configuration Example**:
```yaml
paths:
  - path: "/data"
    stack_threshold: 98      # Trigger at 98% usage
    stack_age_days: 14       # Delete files older than 14 days
```

---

### ✅ 10. Log File Rotation

**Requirement**: Log file rotation setting configurable.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `LoggingCfg` with `RotationDays` in configuration
- Log rotation in `internal/logging/logging.go`
- Automatic cleanup of old rotated logs

**Implementation**:
- `rotateLogsIfNeeded()` checks log age
- `cleanupOldLogs()` removes logs older than rotation days
- Rotated logs named with timestamp

**Configuration Example**:
```yaml
logging:
  rotation_days: 30  # Keep logs for 30 days
```

---

### ✅ 11. Recursive Deletion Flag

**Requirement**: Flag for recursive deletion.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `Recursive` flag in `CleanupOptions`
- Recursive handling in `internal/cleanup/cleanup.go`
- Directory deletion respects recursive flag

**Implementation**:
- `CleanupOptions.Recursive` controls behavior
- When `true`: uses `os.RemoveAll()` for directories
- When `false`: uses `os.Remove()` (empty directories only)

**Configuration Example**:
```yaml
cleanup_options:
  recursive: true  # Enable recursive deletion
```

---

### ✅ 12. Directory Deletion Flag

**Requirement**: Flag for directory deleting.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `DeleteDirs` flag in `CleanupOptions`
- Directory deletion logic in `internal/cleanup/cleanup.go`
- Safety check prevents accidental directory deletion

**Implementation**:
- `CleanupOptions.DeleteDirs` enables directory deletion
- Only deletes directories if flag is enabled
- Logs directory deletions with structured format

**Configuration Example**:
```yaml
cleanup_options:
  delete_dirs: false  # Disable directory deletion (default: false for safety)
```

---

### ✅ 13. Grafana/Prometheus Metrics

**Requirement**: Logs Must be able to leverage Grafana and/or Prometheus for metrics.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- Prometheus metrics endpoint on port 9090
- Metrics defined in `internal/metrics/metrics.go`
- Grafana dashboard JSON provided

**Implementation**:
- `storagesage_files_deleted_total` - Counter
- `storagesage_bytes_freed_total` - Counter
- `storagesage_errors_total` - Counter
- `storagesage_cleanup_duration_seconds` - Histogram

**Metrics Endpoint**: `http://localhost:9090/metrics`

---

### ✅ 14. Configurable Log Rotation Days

**Requirement**: Must rotate configurable amount of days.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `rotation_days` in `LoggingCfg`
- Configurable via YAML
- Automatic rotation and cleanup

**Implementation**:
- Default: 30 days
- Configurable via `logging.rotation_days`
- Old logs automatically removed

---

### ✅ 15. Structured Logging with Date Tags

**Requirement**: Must have date tags and name of the deleted object for each action.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- Structured logging in `internal/cleanup/cleanup.go`
- `logStructured()` function formats logs
- Includes timestamp, path, object name, size, reason

**Implementation**:
- Format: `[timestamp] ACTION path=... object=... size=... reason=...`
- ISO 8601 timestamp format
- Object name extracted from path
- All deletion actions logged

**Example Log Output**:
```
[2024-01-15T10:30:45.123Z] DELETE path=/data/logs/app.log object=app.log size=1024 reason=file
```

---

### ✅ 16. Handle Millions of Files

**Requirement**: Must be able to handle millions of files of all sizes.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- Incremental scanning with `filepath.WalkDir`
- Streaming processing (no full memory load)
- Efficient sorting algorithms
- Resource limits prevent overload

**Implementation**:
- Uses `filepath.WalkDir` for efficient directory traversal
- Processes files incrementally
- Sorts candidates by age for efficient deletion
- CPU throttling prevents system overload

---

### ✅ 17. Stale File Handling (NFS)

**Requirement**: Must be able to deal with stale files. Example: Cannot lock up when trying to access a disconnected nfs filesystem.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `IsNFSStale()` function with timeout
- Error detection for NFS-specific errors
- Graceful skipping of stale files

**Implementation**:
- Timeout-based detection (configurable)
- Detects EIO, ESTALE, ENXIO errors
- Skips stale files during scan and cleanup
- Logs skipped files for visibility

**Configuration**:
```yaml
nfs_timeout_seconds: 5  # 5 second timeout
```

---

### ✅ 18. Resource Limiting (10% CPU)

**Requirement**: Must be resource bound to insure no more than 10% of CPU etc are used when functioning.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `CPULimiter` in `internal/limiter/limiter.go`
- CPU throttling in scheduler
- Systemd CPU quota in service file

**Implementation**:
- `CPULimiter.Throttle()` limits CPU usage
- Configurable via `resource_limits.max_cpu_percent`
- Systemd `CPUQuota=10%` as additional limit
- Throttling during scan and cleanup operations

**Configuration**:
```yaml
resource_limits:
  max_cpu_percent: 10.0  # Maximum 10% CPU usage
```

---

### ✅ 19. Directory Priority

**Requirement**: Prioritize directories when cleaning up. Example: Clean all files older than 14days in /data/work before /data/product.

**Status**: ✅ **COMPLIANT**

**Evidence**:
- `Priority` field in `PathRule`
- Priority-based sorting in `Scan()`
- Lower number = higher priority

**Implementation**:
- Paths sorted by priority before processing
- Priority 1 = highest priority
- Processes high-priority paths first

**Configuration Example**:
```yaml
paths:
  - path: "/data/work"
    priority: 1        # Highest priority
    age_off_days: 14
  - path: "/data/product"
    priority: 2        # Lower priority
    age_off_days: 14
```

---

## Configuration Example

Complete configuration example meeting all requirements:

```yaml
scan_paths:
  - "/var/log"

age_off_days: 14
interval_minutes: 15

paths:
  - path: "/data/work"
    age_off_days: 14
    max_free_percent: 90
    target_free_percent: 80
    priority: 1
    stack_threshold: 98
    stack_age_days: 14
  - path: "/data/product"
    age_off_days: 14
    max_free_percent: 90
    target_free_percent: 80
    priority: 2
    stack_threshold: 98
    stack_age_days: 14

prometheus:
  port: 9090

logging:
  rotation_days: 30

resource_limits:
  max_cpu_percent: 10.0

cleanup_options:
  recursive: true
  delete_dirs: false

nfs_timeout_seconds: 5
```

## Verification Commands

### Check Service Status
```bash
systemctl status storage-sage
```

### View Logs
```bash
journalctl -u storage-sage -f
tail -f /var/log/storage-sage/cleanup.log
```

### Check Metrics
```bash
curl http://localhost:9090/metrics
```

### Test Configuration
```bash
storage-sage --config=/etc/storage-sage/config.yaml --dry-run --once
```

## Compliance Summary

| Requirement | Status | Implementation |
|------------|--------|----------------|
| RedHat 9/10 Compatibility | ✅ | Standard Go, systemd |
| Remove from Any Directory | ✅ | Configurable paths |
| NAS/NFS Support | ✅ | Stale file detection |
| Fault Tolerance (systemctl) | ✅ | Systemd service file |
| BareMetal/Podman/RKE2 | ✅ | Single binary, container-ready |
| Secure GUI | ✅ | HTTPS, JWT, RBAC |
| Age Off Date | ✅ | Configurable age threshold |
| % Free Threshold | ✅ | Disk usage-based cleanup |
| Stacked Cleanup | ✅ | Combined thresholds |
| Log Rotation | ✅ | Configurable rotation |
| Recursive Flag | ✅ | CleanupOptions.Recursive |
| Directory Deletion Flag | ✅ | CleanupOptions.DeleteDirs |
| Grafana/Prometheus | ✅ | Metrics endpoint |
| Configurable Rotation Days | ✅ | logging.rotation_days |
| Structured Logging | ✅ | Date tags, object names |
| Millions of Files | ✅ | Efficient scanning |
| Stale File Handling | ✅ | NFS timeout detection |
| Resource Limiting | ✅ | CPU throttling |
| Directory Priority | ✅ | Priority-based sorting |

**Overall Compliance**: ✅ **100% COMPLIANT**

All 19 requirements have been implemented and verified.


