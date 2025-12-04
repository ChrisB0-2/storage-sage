# StorageSage Test Scripts Guide

## Complete Feature Testing & Demonstration

This guide provides information about all available test scripts and how to demonstrate StorageSage features.

---

## 📋 Available Test Scripts

### 1. **Comprehensive Test Suite** ⭐ RECOMMENDED
**File:** `scripts/comprehensive_test.sh`

**What it tests:** All 46+ features across daemon, API, CLI, and UI subsystems

**Features Covered:**
- ✅ **Daemon Core Features** (D8-D15)
  - Prometheus metrics endpoint
  - Files deleted counter
  - Bytes freed counter
  - Errors counter
  - Cleanup duration histogram
  - Daemon health check

- ✅ **Web API Features** (W2-W19)
  - Health check endpoint
  - Get/update configuration
  - Configuration validation
  - Current metrics retrieval
  - Cleanup status
  - Manual cleanup trigger
  - Deletions log
  - TLS encryption
  - JWT authentication
  - Security headers

- ✅ **Database Query CLI** (Q1-Q7)
  - Recent deletions query
  - Database statistics
  - SQLite schema validation

- ✅ **Security Features** (W15-W19)
  - TLS 1.2/1.3 encryption
  - JWT auth enforcement
  - Security headers (X-Content-Type-Options, X-Frame-Options, HSTS)

- ✅ **Container Health** (C1-C4)
  - Daemon container status
  - Backend container status
  - Loki container status
  - Promtail container status

- ✅ **Logging & Observability** (L1-L2)
  - Loki ready endpoint
  - Promtail ready endpoint

- ✅ **Configuration Management** (CFG1-CFG6)
  - Config file existence
  - Config readability
  - Path-specific rules
  - Cleanup mode settings

- ✅ **Spec Compliance** (MODE1-MODE2, H1-H2, M1-M4, DB1-DB4)
  - Cleanup mode tracking
  - Health endpoints
  - Required metrics
  - Database schema

**Usage:**
```bash
./scripts/comprehensive_test.sh
```

**Expected Output:**
```
===============================================
  STORAGE-SAGE COMPREHENSIVE TEST SUITE
===============================================

Total Tests:    46
Passed:         45 ✅
Failed:         0
Skipped:        1

✅ ALL TESTS PASSED
```

---

### 2. **Quick Test Script** ⚡
**File:** `quick_test.sh`

**What it does:** Rapid testing workflow for creating files and triggering cleanup

**Features Demonstrated:**
- Create old files (15 days old)
- Create large files (100MB each)
- Trigger manual cleanup
- Monitor metrics before/after
- Verify file deletion

**Usage:**
```bash
./quick_test.sh
```

**What happens:**
1. Shows initial metrics
2. Creates 3 old files (15 days old)
3. Triggers cleanup
4. Shows metrics after cleanup
5. Creates 3 large files (300MB total)
6. Triggers cleanup again
7. Shows final metrics
8. Cleans up test files

---

### 3. **Complete Feature Demonstration** 🎬 NEW!
**File:** `demo_all_features.sh`

**What it demonstrates:** Complete walkthrough of ALL StorageSage features with beautiful output

**Features Covered:**
1. **System Status & Health Checks**
   - Docker container status
   - Backend health
   - Daemon health

2. **Authentication & Security**
   - JWT login
   - Security headers
   - Unauthorized access prevention

3. **Prometheus Metrics**
   - Core metrics exposition
   - Spec-required metrics
   - Real-time statistics

4. **Configuration Management**
   - Fetch configuration
   - Configuration validation

5. **Cleanup Operations**
   - Status checking
   - Creating test files
   - Triggering cleanup
   - Verification

6. **Deletion History & Audit**
   - SQLite database queries
   - Deletion log via API

7. **Cleanup Mode Decision Logic**
   - AGE mode
   - DISK-USAGE mode
   - STACK mode (emergency)

8. **Log Aggregation**
   - Loki integration
   - Promtail shipping

9. **Grafana Dashboards**
   - Dashboard access
   - Visualization

10. **Path-Specific Rules**
    - Per-path configuration
    - Priority-based deletion

11. **Container Orchestration**
    - Docker Compose services
    - Volume management

12. **Additional Features**
    - RESTful API endpoints
    - Dry-run mode
    - Resource throttling

**Usage:**
```bash
./demo_all_features.sh
```

**Example Output:**
```
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║          STORAGE-SAGE COMPLETE FEATURE DEMONSTRATION          ║
║                                                                ║
║  Intelligent Automated Storage Cleanup for Enterprise Systems ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. SYSTEM STATUS & HEALTH CHECKS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▶ Checking Docker containers status
  ✓ Backend API is responding
  ✓ Daemon is responding

...
```

---

## 🚀 Getting Started

### Prerequisites
Before running tests, ensure services are running:

```bash
# Start all services
docker-compose up -d

# Or use the start script
./scripts/start-all.sh
```

### Quick Start Testing

1. **Run comprehensive tests:**
   ```bash
   ./scripts/comprehensive_test.sh
   ```

2. **Quick feature demo:**
   ```bash
   ./quick_test.sh
   ```

3. **Full feature demonstration:**
   ```bash
   ./demo_all_features.sh
   ```

---

## 🎯 Feature Categories

### Core Cleanup Features
- **Age-based cleanup:** Delete files older than `age_off_days`
- **Disk-usage cleanup:** Delete oldest files when disk usage exceeds threshold
- **Stack mode:** Emergency cleanup for critical storage situations
- **Priority-based deletion:** Control cleanup order with priorities

### Monitoring & Observability
- **Prometheus metrics:** Real-time statistics and counters
- **Grafana dashboards:** Visual analytics
- **Loki log aggregation:** Centralized log management
- **Health checks:** Container and service health monitoring

### API & Web Interface
- **RESTful API:** Complete HTTP API for all operations
- **JWT Authentication:** Secure token-based auth
- **TLS Encryption:** HTTPS for all API traffic
- **Web UI:** React-based dashboard

### Data Management
- **SQLite Database:** Complete audit trail of deletions
- **Query CLI:** Command-line tool for database queries
- **Deletion Log API:** REST endpoint for deletion history

### Configuration
- **Path-specific rules:** Different policies per directory
- **Dynamic configuration:** Update config via API
- **Configuration validation:** Verify config before applying

---

## 📊 Metrics Available

### Core Metrics
- `storagesage_files_deleted_total` - Total files deleted
- `storagesage_bytes_freed_total` - Total bytes freed
- `storagesage_errors_total` - Total errors
- `storagesage_cleanup_duration_seconds` - Cleanup duration histogram

### Spec-Required Metrics
- `storagesage_daemon_free_space_percent{path}` - Free space per path
- `storagesage_cleanup_last_run_timestamp` - Last cleanup timestamp
- `storagesage_cleanup_last_mode{mode}` - Last cleanup mode
- `storagesage_cleanup_path_bytes_deleted_total{path}` - Bytes deleted per path

### Access Metrics
```bash
# Via daemon
curl http://localhost:9090/metrics

# Via backend API (authenticated)
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/metrics/current
```

---

## 🔧 Manual Testing Examples

### 1. Test Authentication
```bash
# Login
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

# Verify token works
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/config | jq
```

### 2. Trigger Manual Cleanup
```bash
# Trigger
curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# Check status
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/status | jq
```

### 3. Query Deletion History
```bash
# Via API
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8443/api/v1/deletions/log?limit=10" | jq

# Via CLI
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --recent 20

# Via direct SQLite
docker exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT * FROM deletions ORDER BY timestamp DESC LIMIT 10;"
```

### 4. View Metrics
```bash
# All metrics
curl -s http://localhost:9090/metrics | grep storagesage_

# Specific metric
curl -s http://localhost:9090/metrics | grep storagesage_files_deleted_total
```

### 5. Test Cleanup Modes
```bash
# Check current mode
curl -s http://localhost:9090/metrics | grep storagesage_cleanup_last_mode

# The daemon automatically selects mode based on:
# - Free space < stack_threshold → STACK mode
# - Free space < max_free_percent → DISK-USAGE mode
# - Otherwise → AGE mode
```

---

## 🏃 Running Tests in Action

### Option 1: Run All Tests
```bash
# Comprehensive test suite (recommended)
./scripts/comprehensive_test.sh

# Expected: 45/45 tests passing
```

### Option 2: Interactive Demo
```bash
# Beautiful feature demonstration
./demo_all_features.sh

# Shows all features with color-coded output
```

### Option 3: Quick Verification
```bash
# Fast cleanup test
./quick_test.sh

# Creates files, triggers cleanup, verifies deletion
```

### Option 4: Watch Metrics in Real-Time
```bash
# Monitor metrics continuously
./watch_metrics.sh

# Shows real-time updates of cleanup statistics
```

---

## 🎥 What You'll See

### Comprehensive Test Output
```
================================
  DAEMON CORE FEATURES
================================
[D8] Prometheus metrics endpoint accessible... ✅ PASS
[D8a] Files deleted counter metric exists... ✅ PASS
[D8b] Bytes freed counter metric exists... ✅ PASS
[D8c] Errors counter metric exists... ✅ PASS
...

================================
  WEB API FEATURES
================================
[W2] Health check endpoint returns healthy status... ✅ PASS
[W3] Get configuration endpoint... ✅ PASS
[W5] Validate configuration endpoint... ✅ PASS
...

================================
  SECURITY FEATURES
================================
[W17] TLS encryption enabled... ✅ PASS
[W19] JWT authentication required... ✅ PASS
[W15] Security headers present... ✅ PASS
...
```

### Quick Test Output
```
=== StorageSage Quick Test Script ===

1. Initial State:
  Files Deleted: 0
  Bytes Freed: 0.00 MB
  Errors: 0

2. Creating old files (15 days old)...
Created 3 old files

3. Triggering cleanup...
Cleanup triggered, waiting 3 seconds...

4. Results after cleanup:
  Files Deleted: 3
  Bytes Freed: 0.05 MB
  Files remaining: 0
```

### Demo Features Output
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  3. PROMETHEUS METRICS & MONITORING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▶ Core Metrics Exposition
  storagesage_files_deleted_total 42
  storagesage_bytes_freed_total 3145728000
  storagesage_errors_total 0
  storagesage_cleanup_duration_seconds_sum 15.2

  ✓ Files deleted total: 42
  ✓ Bytes freed total: 3000.00 MB
```

---

## 🔍 Troubleshooting

### Tests Failing?

1. **Check services are running:**
   ```bash
   docker-compose ps
   ```

2. **View logs:**
   ```bash
   docker-compose logs storage-sage-daemon
   docker-compose logs storage-sage-backend
   ```

3. **Verify configuration:**
   ```bash
   cat web/config/config.yaml
   ```

4. **Check health endpoints:**
   ```bash
   curl https://localhost:8443/api/v1/health
   curl http://localhost:9090/health
   ```

### Docker Not Running?

```bash
# Start services
docker-compose up -d

# Or use the start script
./scripts/start-all.sh
```

---

## 📚 Additional Resources

- **Main README:** [README.md](README.md)
- **API Documentation:** Check `/api/v1` endpoints
- **Metrics Guide:** Access http://localhost:9090/metrics
- **Grafana Dashboards:** http://localhost:3001
- **Configuration Examples:** `web/config/config.yaml.example`

---

## ✅ Summary

**Three ways to test StorageSage:**

1. **`comprehensive_test.sh`** - Complete automated test suite (46 tests)
2. **`quick_test.sh`** - Fast cleanup verification
3. **`demo_all_features.sh`** - Beautiful interactive demonstration

**All scripts test:**
- ✅ Cleanup operations (AGE/DISK-USAGE/STACK modes)
- ✅ Metrics exposition and monitoring
- ✅ API endpoints and authentication
- ✅ Database audit trail
- ✅ Security features
- ✅ Container orchestration
- ✅ Configuration management
- ✅ Log aggregation

**Start testing now:**
```bash
./scripts/comprehensive_test.sh  # Automated tests
./demo_all_features.sh           # Interactive demo
./quick_test.sh                  # Quick verification
```

Enjoy exploring StorageSage! 🚀
