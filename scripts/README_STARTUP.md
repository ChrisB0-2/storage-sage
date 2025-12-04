# StorageSage Startup Scripts

Comprehensive daemon management scripts with error diagnosis and multi-mode support.

## Overview

Three companion scripts provide complete lifecycle management for the StorageSage daemon:

- **start.sh** - Start daemon with pre-flight checks and health monitoring (supports full-stack startup)
- **stop.sh** - Safely stop daemon across all deployment modes
- **status.sh** - Check daemon status with detailed diagnostics

## Features

### start.sh Features

- **Multi-mode support**: auto-detect, direct binary, Docker Compose, systemd
- **Full-stack startup**: Start all services (daemon + backend + UI + observability) with `--all` flag
- **Pre-flight checks**: binary, config, directories, permissions, ports
- **Runtime diagnostics**: metrics endpoint, process verification, log monitoring
- **Comprehensive error diagnosis**: actionable error messages with suggested fixes
- **Flexible configuration**: environment variables, command-line overrides
- **Multiple run modes**: foreground, background, dry-run, run-once

### stop.sh Features

- **Graceful shutdown**: SIGTERM with configurable timeout
- **Force kill**: Optional force mode for unresponsive daemons
- **Multi-mode**: Stops daemon regardless of deployment method
- **Clean shutdown**: Removes PID files and verifies process termination

### status.sh Features

- **Status detection**: Auto-detects running mode (direct/docker/systemd)
- **Detailed metrics**: CPU, memory, uptime, files deleted, bytes freed
- **Multiple output formats**: Human-readable or JSON
- **Log viewing**: Recent log entries from appropriate source
- **Watch mode**: Continuous status updates every 2 seconds

## Quick Start

### Start Everything (Recommended)

```bash
# Start all services (daemon + backend + UI + observability)
./scripts/start.sh --mode docker --all
```

This starts:
- ✅ **Daemon** - File cleanup service (port 9090)
- ✅ **Backend** - Web API server (port 8443)
- ✅ **Frontend/UI** - Served by backend at `https://localhost:8443`
- ✅ **Loki** - Log aggregation (port 3100, optional)
- ✅ **Promtail** - Log shipper (port 9080, optional)

**Access the UI**: `https://localhost:8443`

### Start Daemon Only

```bash
# Auto-detect best mode and start daemon only
./scripts/start.sh

# Or specify mode explicitly
./scripts/start.sh --mode docker
./scripts/start.sh --mode systemd
./scripts/start.sh --mode direct
```

## Usage

### Starting the Daemon

#### Full-Stack Startup (All Services)

```bash
# Start all services in Docker mode (recommended)
./scripts/start.sh --mode docker --all

# Auto-detect Docker mode and start all
./scripts/start.sh --all

# Start all with verbose output
./scripts/start.sh --mode docker --all --verbose

# Start all with dry-run mode
./scripts/start.sh --mode docker --all --dry-run
```

**Full-Stack Startup Output:**
```
[INFO] Starting all StorageSage services (Docker mode)...
[INFO] Services to start: storage-sage-daemon storage-sage-backend loki promtail
[OK] All services started successfully

Access Points:
  Frontend/UI:  https://localhost:8443
  Backend API:  https://localhost:8443/api/v1
  Daemon Metrics: http://localhost:9090/metrics
  Loki:         http://localhost:3100
```

#### Daemon-Only Startup

```bash
# Auto-detect best mode and start
./scripts/start.sh

# Specify mode explicitly
./scripts/start.sh --mode docker
./scripts/start.sh --mode systemd
./scripts/start.sh --mode direct

# Run in foreground for debuggi
```

### Stopping the Daemon

```bash
# Graceful shutdown (30s timeout)
./scripts/stop.sh

# Force kill if not responding
./scripts/stop.sh --force

# Wait up to 60 seconds before giving up
./scripts/stop.sh --wait 60
```

### Checking Status

```bash
# Basic status check
./scripts/status.sh

# Detailed status with metrics
./scripts/status.sh --verbose

# Show recent logs
./scripts/status.sh --logs --lines 50

# JSON output for scripting
./scripts/status.sh --json

# Continuous monitoring
./scripts/status.sh --watch
```

## Environment Variables

Override default paths using environment variables:

```bash
export STORAGE_SAGE_BINARY=/usr/local/bin/storage-sage
export STORAGE_SAGE_CONFIG=/etc/storage-sage/config.yaml
export STORAGE_SAGE_LOG_DIR=/var/log/storage-sage
export STORAGE_SAGE_DB_DIR=/var/lib/storage-sage
export STORAGE_SAGE_PID_FILE=/var/run/storage-sage.pid

./scripts/start.sh
```

## Deployment Modes

### 1. Direct Binary Mode

Runs the compiled binary directly on the host system.

**Requirements:**
- Binary installed at `/usr/local/bin/storage-sage`
- Config at `/etc/storage-sage/config.yaml`
- Writable log directory: `/var/log/storage-sage`
- Writable database directory: `/var/lib/storage-sage`

**Example:**
```bash
# Build and install
make build
sudo make install

# Start
./scripts/start.sh --mode direct
```

### 2. Docker Compose Mode

Runs the daemon in a Docker container.

**Requirements:**
- Docker and Docker Compose installed
- `docker-compose.yml` in project root
- User in docker group (or sudo access)

**Example:**
```bash
# Start
./scripts/start.sh --mode docker

# Check logs
docker compose logs -f storage-sage-daemon

# Stop
./scripts/stop.sh
```

### 3. Systemd Service Mode

Runs as a systemd service (recommended for production).

**Requirements:**
- Systemd installed
- Service file at `/etc/systemd/system/storage-sage.service`
- Binary and config in standard locations

**Example:**
```bash
# Install service
sudo cp storage-sage.service /etc/systemd/system/
sudo systemctl daemon-reload

# Start
./scripts/start.sh --mode systemd

# Check status
systemctl status storage-sage
journalctl -u storage-sage -f

# Stop
./scripts/stop.sh
```

## Pre-flight Checks

The start script performs comprehensive pre-flight checks:

### Binary Checks (Direct Mode)
- ✓ Binary exists and is executable
- ✓ Binary location: `/usr/local/bin/storage-sage` or `./storage-sage`

### Configuration Checks (Direct Mode)
- ✓ Config file exists and is readable
- ✓ Valid YAML syntax
- ✓ Required fields present
- ✓ Metrics port extracted

### Directory Checks (Direct Mode)
- ✓ Log directory exists and writable
- ✓ Database directory exists and writable
- ✓ Creates directories if missing (with proper permissions)

### Port Checks (Direct Mode)
- ✓ Metrics port available (default: 9090)
- ✓ Shows process using port if occupied

### Process Checks (Direct Mode)
- ✓ No existing daemon running
- ✓ No stale PID files
- ✓ No orphaned processes

### Docker Checks (Docker Mode)
- ✓ Docker installed and daemon running
- ✓ Docker Compose plugin available
- ✓ docker-compose.yml exists
- ✓ User has Docker permissions

### Systemd Checks (Systemd Mode)
- ✓ systemctl available
- ✓ Service file installed

## Runtime Diagnostics

After starting, the script performs health checks:

### Metrics Endpoint Check
- Waits up to 30 seconds for metrics endpoint
- URL: `http://localhost:<port>/metrics`
- Verifies endpoint responds to HTTP requests

### Process Verification
- **Direct**: Checks PID from PID file
- **Docker**: Verifies container running
- **Systemd**: Checks service active state

### Log File Check
- Verifies log file exists
- Confirms recent writes (modified in last 10 seconds)

## Error Diagnosis

When errors occur, the script provides detailed diagnostics:

### Binary Not Found
```
[ERROR] Failed to start StorageSage
========================================
Error: Binary not found

Diagnosis:
  - Searched paths:
    * /usr/local/bin/storage-sage
    * /home/user/projects/storage-sage/storage-sage
  - Binary exists: NO

Suggested fixes:
  1. Install StorageSage:
     cd /home/user/projects/storage-sage
     make build
     sudo make install

  2. Or specify binary location:
     export STORAGE_SAGE_BINARY=/path/to/storage-sage
     ./scripts/start.sh

  3. Or use Docker mode:
     ./scripts/start.sh --mode docker
```

### Permission Denied
```
[ERROR] Failed to start StorageSage
========================================
Error: Permission denied

Diagnosis:
  - Directory exists: YES
  - Directory writable: NO
  - Current user: user (UID 1000)
  - Required: storage-sage user or writable by current user

Suggested fixes:
  1. Fix ownership:
     sudo chown -R $(whoami):$(whoami) /var/log/storage-sage

  2. Fix permissions:
     sudo chmod 755 /var/log/storage-sage

  3. Or run as correct user:
     sudo -u storage-sage ./scripts/start.sh
```

### Port in Use
```
[ERROR] Failed to start StorageSage
========================================
Error: Port in use

Diagnosis:
  - Port: 9090
  - Process using port:
    storage-sage 12345 user ... TCP *:9090

Suggested fixes:
  1. Check if already running:
     ./scripts/status.sh

  2. Stop existing instance:
     ./scripts/stop.sh

  3. Change port in config:
     vim /etc/storage-sage/config.yaml
     # Edit prometheus.port to different value
```

## Success Output

When startup succeeds:

```
[INFO] StorageSage Startup Script v1.0
[INFO] ========================================
[INFO] Running pre-flight checks...
[OK] Binary found: /usr/local/bin/storage-sage
[OK] Config file found: /etc/storage-sage/config.yaml
[OK] Config validation: passed
[OK] Log directory writable: /var/log/storage-sage
[OK] Database directory writable: /var/lib/storage-sage
[OK] Port 9090 available
[OK] No existing daemon process found

[SUCCESS] All pre-flight checks passed

[INFO] Starting StorageSage daemon...
[INFO] Mode: direct (binary execution)
[INFO] Command: /usr/local/bin/storage-sage --config /etc/storage-sage/config.yaml
[INFO] Waiting for daemon to initialize (max 30s)...
[OK] Daemon started with PID: 12345

[INFO] Running runtime diagnostics...

[OK] Metrics endpoint responding: http://localhost:9090/metrics
[OK] Daemon process running: PID 12345
[OK] Log file being written: /var/log/storage-sage/cleanup.log

[SUCCESS] StorageSage started successfully!
========================================
  Mode: Direct (binary execution)
  PID: 12345
  PID File: /var/run/storage-sage.pid
  Config: /etc/storage-sage/config.yaml
  Log: /var/log/storage-sage/cleanup.log
  Metrics: http://localhost:9090/metrics
  Database: /var/lib/storage-sage/deletions.db
========================================

[INFO] Useful commands:
  View logs:    tail -f /var/log/storage-sage/cleanup.log
  Check status: ./scripts/status.sh
  Stop daemon:  ./scripts/stop.sh
  View metrics: curl http://localhost:9090/metrics
```

## Status Output

### Basic Status
```bash
$ ./scripts/status.sh

========================================
  StorageSage Daemon Status
========================================

[✓] Daemon is RUNNING

  Mode: systemd
  PID: 12345
  Started: Wed 2025-11-20 15:30:45 PST

  Metrics Endpoint: http://localhost:9090/metrics
  Metrics Status: available
  Config: /etc/storage-sage/config.yaml
```

### Detailed Status
```bash
$ ./scripts/status.sh --verbose

[Previous output plus:]

Detailed Information:
========================================

Configuration:
  Path: /etc/storage-sage/config.yaml
  Size: 1.2K
  Modified: 2025-11-20 15:25:33

Logging:
  Log File: /var/log/storage-sage/cleanup.log
  Size: 45M
  Modified: 2025-11-20 16:42:15

Database:
  Path: /var/lib/storage-sage/deletions.db
  Size: 128K
  Modified: 2025-11-20 16:42:10

Metrics:
  Endpoint: http://localhost:9090/metrics
  Files Deleted (total): 1523
  Bytes Freed (total): 4.2GiB
  Scan Errors: 0

Process:
  PID: 12345
  CPU: 2.3%
  Memory: 0.8%
  RSS: 24.5MiB
```

### JSON Status
```bash
$ ./scripts/status.sh --json
{
  "daemon": {
    "running": true,
    "mode": "systemd",
    "pid": "12345"
  },
  "config": {
    "path": "/etc/storage-sage/config.yaml",
    "exists": true
  },
  "metrics": {
    "endpoint": "http://localhost:9090/metrics",
    "status": "available",
    "port": 9090
  },
  "paths": {
    "log_dir": "/var/log/storage-sage",
    "db_dir": "/var/lib/storage-sage",
    "pid_file": "/var/run/storage-sage.pid"
  }
}
```

## Integration with Existing Scripts

These scripts integrate seamlessly with existing StorageSage tools:

```bash
# Start daemon
./scripts/start.sh

# Run comprehensive tests
./scripts/comprehensive_test.sh

# Check compliance
./scripts/verify_daemon_compliance.sh

# Monitor cleanup
./scripts/monitor-cleanup.sh

# Stop daemon
./scripts/stop.sh
```

## Troubleshooting

### Script Not Executable
```bash
chmod +x scripts/{start,stop,status}.sh
```

### Python Not Available (for YAML validation)
The scripts will still work but skip YAML syntax validation. Install Python 3 for full functionality:
```bash
sudo apt install python3 python3-yaml  # Debian/Ubuntu
sudo yum install python3 python3-pyyaml  # RHEL/CentOS
```

### Permission Issues
Run with sudo or fix directory permissions:
```bash
sudo ./scripts/start.sh

# Or fix permissions
sudo chown -R $(whoami):$(whoami) /var/log/storage-sage /var/lib/storage-sage
```

### Docker Permission Denied
Add user to docker group:
```bash
sudo usermod -aG docker $(whoami)
newgrp docker
```

## Advanced Usage

### Custom Configuration
```bash
# Use custom config location
./scripts/start.sh --config /custom/path/config.yaml

# Use environment variable
export STORAGE_SAGE_CONFIG=/custom/path/config.yaml
./scripts/start.sh
```

### Background vs Foreground
```bash
# Background mode (default for direct mode)
./scripts/start.sh --mode direct --background

# Foreground mode (for debugging)
./scripts/start.sh --mode direct --foreground --verbose
```

### Monitoring and Automation
```bash
# Continuous status monitoring
./scripts/status.sh --watch

# Automated health check
if ./scripts/status.sh --json | jq -e '.daemon.running == true' > /dev/null; then
  echo "Daemon is healthy"
else
  echo "Daemon is down, restarting..."
  ./scripts/start.sh
fi
```

### Log Integration
```bash
# View combined status and logs
./scripts/status.sh --verbose --logs --lines 50

# Follow logs by mode
# Direct/Systemd:
tail -f /var/log/storage-sage/cleanup.log

# Docker:
docker compose logs -f storage-sage-daemon

# Systemd:
journalctl -u storage-sage -f
```

## Exit Codes

All scripts use standard exit codes:

- **0**: Success
- **1**: Error or daemon not running (status.sh)

Examples:
```bash
# Start daemon and check success
if ./scripts/start.sh; then
  echo "Started successfully"
fi

# Check if daemon is running
if ./scripts/status.sh > /dev/null 2>&1; then
  echo "Daemon is running"
else
  echo "Daemon is not running"
fi

# Stop daemon with force if needed
./scripts/stop.sh || ./scripts/stop.sh --force
```

## Architecture

### start.sh Flow
```
1. Parse arguments
2. Detect/validate mode
3. Run pre-flight checks
   - Binary/Docker/Systemd checks
   - Config validation
   - Directory permissions
   - Port availability
   - Process checks
4. Start daemon (mode-specific)
5. Run health checks
   - Wait for metrics endpoint
   - Verify process running
   - Check log file
6. Display summary
```

### stop.sh Flow
```
1. Parse arguments
2. Try stopping in order:
   a. Systemd (if active)
   b. Docker (if container running)
   c. PID file (if exists)
   d. Process name (fallback)
3. Send SIGTERM
4. Wait for shutdown (configurable timeout)
5. Force kill if requested and needed
6. Clean up PID file
7. Verify stopped
```

### status.sh Flow
```
1. Parse arguments
2. Detect daemon mode:
   a. Check systemd
   b. Check Docker
   c. Check direct (PID file)
   d. Check direct (process name)
3. Gather metrics
4. Display status (basic/detailed/JSON)
5. Show logs if requested
6. Exit with appropriate code
```

## Files Created

- `scripts/start.sh` - Main startup script (1096 lines)
- `scripts/stop.sh` - Daemon stop script (307 lines)
- `scripts/status.sh` - Status checking script (690 lines)
- `scripts/README_STARTUP.md` - This documentation

## System Requirements

- Bash 4.0+
- Standard UNIX utilities (ps, grep, sed, awk, curl, etc.)
- Python 3 (optional, for YAML validation)
- Docker & Docker Compose (for Docker mode)
- systemd (for systemd mode)

## Security Considerations

1. **PID File**: Located in `/var/run` (requires appropriate permissions)
2. **Log Directory**: Writable by daemon user
3. **Database Directory**: Writable by daemon user
4. **Systemd Service**: Runs with restricted privileges (see storage-sage.service)
5. **Docker**: Runs as UID 1000:1000 by default

## Contributing

When modifying these scripts:

1. Maintain strict error handling (`set -euo pipefail`)
2. Add comprehensive error diagnosis for new failure modes
3. Update this README with new features
4. Test all three deployment modes
5. Ensure backward compatibility
6. Follow existing color scheme (GREEN/RED/YELLOW/BLUE/CYAN)

## License

Same as StorageSage project.
