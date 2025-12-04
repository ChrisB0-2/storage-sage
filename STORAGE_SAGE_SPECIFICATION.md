# StorageSage Daemon Specification

**Version:** 1.0  
**Last Updated:** $(date)  
**Based on:** Codebase analysis of storage-sage v1.0

## Overview

StorageSage is a filesystem cleanup daemon that automatically removes old files based on configurable age thresholds and disk space requirements. It runs continuously, scanning specified directories and deleting files that exceed the configured age limit.

## Core Responsibilities

1. **File Scanning**: Scan configured filesystem paths for files older than specified age thresholds
2. **File Deletion**: Delete files that meet deletion criteria (age and free space requirements)
3. **Metrics Exposure**: Expose Prometheus metrics for monitoring and observability
4. **Logging**: Log all operations to file and stdout
5. **Configuration Management**: Load and validate configuration from YAML file
6. **Signal Handling**: Gracefully handle SIGTERM and SIGINT for clean shutdown

## Expected Inputs

### Configuration File
- **Format**: YAML
- **Default Path**: `/etc/storage-sage/config.yaml`
- **Configurable**: Via `--config` command-line flag
- **Required Fields**:
  - `scan_paths` or `paths`: List of directories to scan
  - `age_off_days`: Maximum age in days before deletion
  - `interval_minutes`: Cleanup cycle interval
  - `prometheus.port`: Prometheus metrics server port

### Command-Line Arguments
- `--config`: Path to configuration file (default: `/etc/storage-sage/config.yaml`)
- `--dry-run`: Log actions without deleting files
- `--once`: Run a single cleanup cycle and exit
- `--version`: Print version information and exit

### Signals
- `SIGTERM`: Graceful shutdown request
- `SIGINT`: Graceful shutdown request (interrupt)

## Expected Outputs

### Logs
- **Location**: `/var/log/storage-sage/cleanup.log`
- **Format**: Standard log format with timestamps
- **Also**: Written to stdout
- **Content**:
  - Startup messages
  - Cleanup cycle completion messages
  - File deletion logs (or dry-run logs)
  - Error messages

### Metrics
- **Endpoint**: `http://localhost:{port}/metrics`
- **Format**: Prometheus exposition format
- **Metrics**:
  - `storagesage_files_deleted_total`: Counter of files deleted
  - `storagesage_bytes_freed_total`: Counter of bytes freed
  - `storagesage_errors_total`: Counter of errors encountered
  - `storagesage_cleanup_duration_seconds`: Histogram of cleanup cycle durations

### Exit Codes
- `0`: Success
- `1`: Error (configuration error, runtime error)

## Health Indicators

### Process Health
- Process is running (check via `ps`, `systemctl status`)
- Process responds to signals (SIGTERM/SIGINT)
- Process does not crash on errors

### Functional Health
- Cleanup cycles complete successfully
- Metrics are updated after each cycle
- Logs are written regularly
- Files are deleted according to age criteria (in non-dry-run mode)

### Operational Health
- Metrics endpoint is accessible
- Log files are being written
- Configuration is valid
- Scan paths are accessible

## Behavior Specifications

### Startup Sequence
1. Parse command-line arguments
2. Load configuration from file
3. Validate configuration
4. Initialize logging
5. Initialize metrics
6. Start Prometheus metrics server
7. Set up signal handlers (SIGTERM, SIGINT)
8. Run cleanup cycle(s)

### Cleanup Cycle
1. Scan configured paths for files
2. Identify files older than `age_off_days`
3. Verify files are within allowed paths (security check)
4. Delete files (or log in dry-run mode)
5. Update metrics
6. Log cycle completion

### Shutdown Sequence
1. Receive SIGTERM or SIGINT
2. Cancel context
3. Wait for current cycle to complete (if running)
4. Shutdown metrics server (with 5-second timeout)
5. Log shutdown message
6. Exit

### Error Handling
- Configuration errors: Log error and exit with code 1
- Scan errors: Log error, increment error counter, continue
- Delete errors: Log error, increment error counter, continue with next file
- Metrics server errors: Log error, increment error counter, continue operation

## Configuration Specification

### YAML Schema
```yaml
scan_paths:
  - "/absolute/path/to/scan"
age_off_days: 7
min_free_percent: 10
interval_minutes: 15
paths:
  - path: "/absolute/path/to/scan"
    age_off_days: 7
    min_free_percent: 10
prometheus:
  port: 9090
```

### Validation Rules
- `scan_paths` or `paths` must be specified (at least one)
- All paths must be absolute (start with `/`)
- `age_off_days` must be non-negative
- `interval_minutes` must be positive (default: 15)
- `prometheus.port` must be valid port number (default: 9090)

### Defaults
- `interval_minutes`: 15 (if not specified or <= 0)
- `prometheus.port`: 9090 (if not specified or 0)

## Operational Modes

### Continuous Mode (Default)
- Runs cleanup cycles at configured interval
- Continues until interrupted (SIGTERM/SIGINT)
- Used for daemon operation

### Single Run Mode (`--once`)
- Runs one cleanup cycle
- Exits after cycle completes
- Useful for testing or manual runs

### Dry-Run Mode (`--dry-run`)
- Logs actions without deleting files
- All other functionality remains the same
- Useful for testing and validation

## Security Specifications

### Path Validation
- Only files within configured `scan_paths` or `paths` are considered for deletion
- Path traversal attempts are prevented (relative paths like `../` are rejected)
- Absolute paths are required and validated

### File Deletion Safety
- Files are only deleted if they are within allowed paths
- Unsafe paths are logged and skipped
- Dry-run mode allows testing without actual deletion

## Performance Specifications

### Resource Usage
- Memory: Should be minimal (scan and process files incrementally)
- CPU: Should be low when idle, moderate during scan/delete operations
- Disk I/O: Should be minimal except during cleanup cycles
- File Descriptors: Should be managed efficiently (files closed after processing)

### Scalability
- Should handle large directories (thousands of files)
- Should handle deep directory structures
- Should complete cycles within reasonable time (depends on file count and disk speed)

## Monitoring Specifications

### Metrics
- All metrics must be exposed in Prometheus format
- Metrics must update after each cleanup cycle
- Error metrics must increment on errors

### Logging
- Logs must be written to file and stdout
- Logs must include timestamps
- Logs must include relevant context (file paths, counts, etc.)

## Compliance Requirements

### Process Management
- Must start successfully with valid configuration
- Must handle signals gracefully
- Must not crash on expected errors
- Must clean up resources on shutdown

### Storage Operations
- Must respect dry-run mode (no deletion)
- Must only delete files within configured paths
- Must respect age thresholds
- Must handle permission errors gracefully

### API/Interface
- Must expose Prometheus metrics endpoint
- Must return valid Prometheus format
- Must include all required metrics
- Must update metrics after operations

### Logging
- Must write logs to file
- Must write logs to stdout
- Must include startup messages
- Must include cycle completion messages

### Configuration
- Must validate configuration
- Must reject invalid configuration
- Must apply defaults when values missing
- Must handle missing files gracefully

### Error Handling
- Must not crash on scan errors
- Must continue operation after errors
- Must log errors appropriately
- Must increment error metrics

## Non-Requirements

The following are NOT part of the specification:
- PID file creation (not implemented)
- Auto-restart on crash (handled by systemd)
- Authentication/authorization (no API endpoints)
- Rate limiting (not applicable)
- Data persistence (no database)
- Retry logic (errors are logged and skipped)
- Data integrity checks (filesystem handles this)
- Storage quotas (not implemented, uses filesystem)

## Testing Requirements

### Unit Tests
- Configuration validation
- Path validation
- Age calculation
- File scanning logic

### Integration Tests
- Full cleanup cycles
- Metrics exposure
- Logging
- Signal handling

### Compliance Tests
- Process lifecycle
- Storage operations
- API compliance
- Logging compliance
- Configuration compliance
- Error handling

## References

- Main entry point: `cmd/storage-sage/main.go`
- Scheduler: `internal/scheduler/scheduler.go`
- Configuration: `internal/config/config.go`
- Metrics: `internal/metrics/metrics.go`
- Logging: `internal/logging/logging.go`
- Scanning: `internal/scan/scan.go`
- Cleanup: `internal/cleanup/cleanup.go`

