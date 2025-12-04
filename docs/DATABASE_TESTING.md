# StorageSage Database Testing Guide

## Overview

This guide covers comprehensive testing of the StorageSage SQLite database system, including unit tests, integration tests, performance benchmarks, and operational procedures.

## Architecture

### Database Stack

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Volume                        │
│                  storage-sage-db                        │
│  ┌───────────────────────────────────────────────────┐  │
│  │ /var/lib/storage-sage/deletions.db                │  │
│  │ /var/lib/storage-sage/deletions.db-wal            │  │
│  │ /var/lib/storage-sage/deletions.db-shm            │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         ▲                                    ▲
         │                                    │
    [RW Mount]                           [RO Mount]
         │                                    │
┌────────┴────────┐                  ┌────────┴────────┐
│  Daemon         │                  │  Backend        │
│  Container      │                  │  Container      │
│                 │                  │                 │
│ - Records       │                  │ - Queries       │
│   deletions     │                  │   history       │
│ - WAL writer    │                  │ - Serves API    │
│                 │                  │ - Read-only     │
└─────────────────┘                  └─────────────────┘
```

### Database Configuration

- **Engine**: SQLite3 (version 3.x)
- **Journal Mode**: WAL (Write-Ahead Logging)
- **Synchronous Mode**: NORMAL (balance performance/safety)
- **Schema Version**: 2

### Tables

#### deletions
Primary table storing all deletion events.

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | INTEGER | NO | Primary key (autoincrement) |
| timestamp | DATETIME | NO | When deletion was evaluated |
| action | TEXT | NO | DELETE, SKIP, or ERROR |
| path | TEXT | NO | File/directory path |
| file_name | TEXT | YES | Basename of path |
| object_type | TEXT | NO | file, directory, empty_directory |
| size | INTEGER | NO | Size in bytes |
| deletion_reason | TEXT | YES | Human-readable reason |
| primary_reason | TEXT | YES | age_threshold, disk_threshold, stacked_cleanup, combined |
| mode | TEXT | YES | AGE, DISK, STACK |
| priority | INTEGER | YES | Priority from path rule |
| age_days | INTEGER | YES | Actual age in days |
| age_threshold_days | INTEGER | YES | Configured age threshold |
| actual_age_days | INTEGER | YES | Actual age at evaluation |
| disk_threshold_percent | REAL | YES | Configured disk threshold |
| actual_disk_percent | REAL | YES | Actual disk usage |
| stacked_threshold_percent | REAL | YES | Stacked cleanup threshold |
| stacked_age_days | INTEGER | YES | Stacked cleanup age |
| path_rule | TEXT | YES | Matching path rule |
| error_message | TEXT | YES | Error details if action=ERROR |
| created_at | DATETIME | NO | Record insertion time |

**Indexes:**
- `idx_timestamp` on timestamp
- `idx_action` on action
- `idx_path` on path
- `idx_primary_reason` on primary_reason
- `idx_mode` on mode
- `idx_size` on size
- `idx_created_at` on created_at

#### schema_version
Tracks database schema migrations.

| Column | Type | Description |
|--------|------|-------------|
| version | INTEGER | Schema version (primary key) |
| applied_at | DATETIME | When schema was applied |

---

## Test Suite

### 1. Unit Tests (Go)

Located in: `internal/database/database_test.go`

#### Running Unit Tests

```bash
# Run all database tests
go test ./internal/database/

# With verbose output
go test -v ./internal/database/

# With race detection
go test -race ./internal/database/

# With coverage
go test -cover ./internal/database/

# Coverage report
go test -coverprofile=coverage.out ./internal/database/
go tool cover -html=coverage.out -o coverage.html
```

#### Test Categories

**Connection Tests**
- `TestDatabaseCreation`: Verifies database file creation
- `TestWALModeEnabled`: Validates WAL mode configuration
- `TestSchemaCreation`: Checks table and index creation

**CRUD Tests**
- `TestRecordDeletion`: Basic insertion
- `TestRecordAllFieldTypes`: All field combinations
- `TestQueryMethods`: All query functions
- `TestPaginationMethods`: Pagination functionality
- `TestNullFieldHandling`: Nullable field handling

**Performance Tests**
- `TestBulkInsertPerformance`: 10,000+ record insertion
- `TestIndexUtilization`: Index usage verification
- `TestVacuum`: Database optimization

**Concurrency Tests**
- `TestConcurrentReads`: Multiple simultaneous readers
- `TestConcurrentReadWrite`: Mixed read/write operations

**Error Handling**
- `TestDatabaseErrorHandling`: Invalid paths, permissions
- `TestDatabaseStats`: Statistics gathering

### 2. Integration Tests (Bash)

Located in: `scripts/test_sqldb.sh`

#### Running Integration Tests

```bash
# Full test suite (unit + integration)
./scripts/test_sqldb.sh

# Only unit tests
./scripts/test_sqldb.sh --unit-only

# Only integration tests
./scripts/test_sqldb.sh --integration-only

# Verbose output
./scripts/test_sqldb.sh --verbose

# Don't cleanup test containers
./scripts/test_sqldb.sh --no-cleanup
```

#### Integration Test Categories

1. **Docker Service Checks**
   - Verify daemon container is running
   - Verify backend container is running

2. **Database Volume Checks**
   - Volume existence
   - Volume mounts in both containers
   - Mount permissions (RW vs RO)

3. **Database File Checks**
   - Database file existence
   - WAL file presence (deletions.db-wal)
   - Shared memory file (deletions.db-shm)
   - File permissions

4. **Schema Checks**
   - Table existence (deletions, schema_version)
   - Index count (7 expected)
   - Schema version (2)
   - WAL mode enabled

5. **Write Tests**
   - Create test files
   - Verify database records

6. **Read Tests**
   - Backend can read database
   - Backend cannot write (read-only mount)

7. **API Endpoint Tests**
   - Health check
   - Database API endpoints (requires auth)

8. **Performance Tests**
   - Database size
   - Page count/size
   - Integrity check

9. **Concurrent Access**
   - Simultaneous reads from daemon and backend

10. **Backup/Restore**
    - Create backup
    - Verify backup integrity

---

## Manual Testing Procedures

### Verify Database Initialization

```bash
# Check if database exists in daemon container
docker compose exec storage-sage-daemon ls -lah /var/lib/storage-sage/

# Expected output:
# -rw-r--r-- 1 user user  32K deletions.db
# -rw-r--r-- 1 user user  32K deletions.db-wal
# -rw-r--r-- 1 user user  32K deletions.db-shm
```

### Check WAL Mode

```bash
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA journal_mode;"

# Expected: wal
```

### Query Database Directly

```bash
# Record count
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT COUNT(*) FROM deletions;"

# Recent deletions
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT timestamp, action, path, size FROM deletions ORDER BY timestamp DESC LIMIT 10;"

# Deletions by action
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT action, COUNT(*) FROM deletions GROUP BY action;"

# Deletions by primary reason
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT primary_reason, COUNT(*) FROM deletions GROUP BY primary_reason;"

# Total space freed
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT SUM(size) FROM deletions WHERE action='DELETE';"
```

### Verify Cross-Container Access

```bash
# Read from daemon (should work)
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT COUNT(*) FROM deletions;"

# Read from backend (should work)
docker compose exec storage-sage-backend \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT COUNT(*) FROM deletions;"

# Try write from backend (should fail - read-only mount)
docker compose exec storage-sage-backend \
  sh -c "echo 'test' > /var/lib/storage-sage/test.txt"
# Expected: cannot create file: Read-only file system
```

### Check Database Health

```bash
# Integrity check
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA integrity_check;"

# Expected: ok

# Foreign key check (none currently)
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA foreign_key_check;"

# Quick check
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA quick_check;"
```

### Database Statistics

```bash
# Database size
docker compose exec storage-sage-daemon \
  stat -c "%s" /var/lib/storage-sage/deletions.db

# Page count and size
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA page_count; PRAGMA page_size;"

# Schema info
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  ".schema deletions"
```

---

## Performance Benchmarking

### Insert Performance

```bash
# Run bulk insert test
go test -v -run TestBulkInsertPerformance ./internal/database/

# Expected: >100 inserts/second
```

### Query Performance

```bash
# Test query with EXPLAIN QUERY PLAN
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "EXPLAIN QUERY PLAN SELECT * FROM deletions WHERE action='DELETE';"

# Should show: SEARCH deletions USING INDEX idx_action (action=?)
```

### Concurrent Read Test

```bash
# Launch 10 concurrent readers
for i in {1..10}; do
  docker compose exec storage-sage-daemon \
    sqlite3 /var/lib/storage-sage/deletions.db \
    "SELECT COUNT(*) FROM deletions;" &
done
wait

# All should complete without errors
```

---

## Operational Procedures

### Database Backup

```bash
# Create backup using SQLite backup command
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  ".backup /var/lib/storage-sage/deletions_backup_$(date +%Y%m%d_%H%M%S).db"

# Copy backup to host
docker cp storage-sage-daemon:/var/lib/storage-sage/deletions_backup_*.db ./backups/
```

### Database Restore

```bash
# Stop services
docker compose down

# Copy backup to volume
docker run --rm -v storage-sage-db:/data -v $(pwd)/backups:/backups \
  alpine cp /backups/deletions_backup_YYYYMMDD_HHMMSS.db /data/deletions.db

# Restart services
docker compose up -d
```

### Database Vacuum

```bash
# Run VACUUM to reclaim space and defragment
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "VACUUM;"

# Check size before/after
docker compose exec storage-sage-daemon \
  du -sh /var/lib/storage-sage/deletions.db
```

### Purge Old Records

```bash
# Delete records older than 90 days
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "DELETE FROM deletions WHERE timestamp < datetime('now', '-90 days');"

# Run VACUUM to reclaim space
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "VACUUM;"
```

### Checkpoint WAL

```bash
# Manually checkpoint WAL (merge into main database)
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA wal_checkpoint(FULL);"

# Check WAL size
docker compose exec storage-sage-daemon \
  ls -lh /var/lib/storage-sage/deletions.db-wal
```

---

## Troubleshooting

### Database Locked Errors

**Symptom**: `SQLITE_BUSY: database is locked`

**Cause**: WAL mode not enabled, or too many concurrent writers

**Solution**:
```bash
# Verify WAL mode
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA journal_mode;"

# Should return: wal

# If not, enable WAL mode
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA journal_mode=WAL;"
```

### Permission Denied

**Symptom**: `unable to open database file`

**Cause**: Incorrect volume permissions

**Solution**:
```bash
# Check permissions
docker compose exec storage-sage-daemon ls -la /var/lib/storage-sage/

# Fix ownership (user 1000:1000)
docker compose exec storage-sage-daemon chown -R 1000:1000 /var/lib/storage-sage/
```

### Database Corruption

**Symptom**: `PRAGMA integrity_check` returns errors

**Solution**:
```bash
# 1. Stop services
docker compose down

# 2. Restore from backup
docker run --rm -v storage-sage-db:/data -v $(pwd)/backups:/backups \
  alpine cp /backups/deletions_backup_latest.db /data/deletions.db

# 3. Restart services
docker compose up -d

# 4. Verify integrity
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA integrity_check;"
```

### Read-Only Mount Issues (Backend)

**Symptom**: Backend container cannot read database

**Cause**: Incorrect mount configuration

**Solution**:
```bash
# Verify mount in docker-compose.yml
grep -A2 "storage-sage-backend:" docker-compose.yml | grep "storage-sage-db"

# Should show: - storage-sage-db:/var/lib/storage-sage:ro

# Recreate containers
docker compose down
docker compose up -d
```

### WAL Files Growing Too Large

**Symptom**: deletions.db-wal file is > 100MB

**Cause**: Infrequent checkpoints

**Solution**:
```bash
# Force checkpoint
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA wal_checkpoint(TRUNCATE);"

# Set auto-checkpoint limit (pages)
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA wal_autocheckpoint=1000;"
```

---

## Best Practices

### Development

1. **Always run unit tests** before committing changes:
   ```bash
   go test -race ./internal/database/
   ```

2. **Use coverage reports** to identify untested code:
   ```bash
   go test -coverprofile=coverage.out ./internal/database/
   go tool cover -html=coverage.out
   ```

3. **Test concurrency** when modifying database code:
   ```bash
   go test -race -run TestConcurrent ./internal/database/
   ```

### Production

1. **Regular backups**: Daily automated backups
   ```bash
   # Add to cron
   0 2 * * * /path/to/backup_database.sh
   ```

2. **Monitor database size**: Alert when > 1GB
   ```bash
   db_size=$(docker compose exec storage-sage-daemon stat -c "%s" /var/lib/storage-sage/deletions.db)
   if [ $db_size -gt 1073741824 ]; then
     echo "Database size exceeds 1GB"
   fi
   ```

3. **Periodic vacuum**: Monthly optimization
   ```bash
   # First Sunday of month
   0 3 1-7 * * [ $(date +\%u) -eq 7 ] && docker compose exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "VACUUM;"
   ```

4. **Retention policy**: Delete records older than 90 days
   ```bash
   # Weekly cleanup
   0 4 * * 0 docker compose exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db "DELETE FROM deletions WHERE timestamp < datetime('now', '-90 days');"
   ```

---

## Performance Tuning

### Index Optimization

```sql
-- Analyze index usage
EXPLAIN QUERY PLAN SELECT * FROM deletions WHERE action='DELETE';

-- Should use index: SEARCH deletions USING INDEX idx_action
```

### Query Optimization

```sql
-- Use pagination for large result sets
SELECT * FROM deletions ORDER BY timestamp DESC LIMIT 100 OFFSET 0;

-- Use indexes in WHERE clauses
SELECT * FROM deletions WHERE timestamp > datetime('now', '-7 days');

-- Aggregate queries
SELECT primary_reason, COUNT(*), SUM(size)
FROM deletions
WHERE action='DELETE'
GROUP BY primary_reason;
```

### Connection Pool Tuning

Go's `database/sql` package handles connection pooling automatically.

```go
// In database.go initialization:
db.SetMaxOpenConns(25)    // Maximum open connections
db.SetMaxIdleConns(5)     // Idle connection pool size
db.SetConnMaxLifetime(5 * time.Minute)
```

---

## Security Considerations

### Access Control

- **Daemon container**: Read-write access (records deletions)
- **Backend container**: Read-only access (serves queries)
- **No external access**: Database not exposed outside Docker network

### Data Validation

All inputs are validated before insertion:
- Path sanitization
- Size range checks (non-negative)
- Action type validation (DELETE, SKIP, ERROR only)
- Timestamp validation

### SQL Injection Prevention

- **Parameterized queries**: All queries use `?` placeholders
- **No string concatenation**: Never build SQL with string concat
- **Input sanitization**: All user inputs are sanitized

Example:
```go
// GOOD: Parameterized query
db.Exec("SELECT * FROM deletions WHERE path = ?", userPath)

// BAD: String concatenation (vulnerable to SQL injection)
db.Exec("SELECT * FROM deletions WHERE path = '" + userPath + "'")
```

---

## Metrics and Monitoring

### Key Metrics

1. **Record Count**: Total deletion records
   ```sql
   SELECT COUNT(*) FROM deletions;
   ```

2. **Space Freed**: Total bytes deleted
   ```sql
   SELECT SUM(size) FROM deletions WHERE action='DELETE';
   ```

3. **Deletion Rate**: Deletions per day
   ```sql
   SELECT DATE(timestamp), COUNT(*)
   FROM deletions
   WHERE action='DELETE'
   GROUP BY DATE(timestamp)
   ORDER BY DATE(timestamp) DESC;
   ```

4. **Database Size**: File size on disk
   ```bash
   stat -c "%s" /var/lib/storage-sage/deletions.db
   ```

5. **WAL Size**: Write-ahead log size
   ```bash
   stat -c "%s" /var/lib/storage-sage/deletions.db-wal
   ```

### Prometheus Metrics (Future)

Potential metrics to expose:
- `storage_sage_db_records_total`
- `storage_sage_db_size_bytes`
- `storage_sage_db_wal_size_bytes`
- `storage_sage_db_query_duration_seconds`
- `storage_sage_db_insert_duration_seconds`

---

## References

- [SQLite WAL Mode](https://www.sqlite.org/wal.html)
- [SQLite Pragma Statements](https://www.sqlite.org/pragma.html)
- [Go database/sql Package](https://pkg.go.dev/database/sql)
- [mattn/go-sqlite3 Driver](https://github.com/mattn/go-sqlite3)
