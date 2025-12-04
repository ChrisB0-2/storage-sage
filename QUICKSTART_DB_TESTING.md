# Quick Start: Database Testing

## ⚠️ **IMPORTANT: First Run Will Be Slow (30-120s)**

The database tests use **CGo** (C bindings for SQLite), which requires compilation on first run.

- **First run**: 30-120 seconds (compiling SQLite C code) ⏳
- **Subsequent runs**: <5 seconds (cached) ⚡

**This is NORMAL!** See [DATABASE_TEST_ISSUE_ANALYSIS.md](DATABASE_TEST_ISSUE_ANALYSIS.md) for full explanation.

## 🚀 **Run All Tests**

```bash
# Complete test suite (unit + integration)
./scripts/test_sqldb.sh

# NOTE: First run will compile CGo - be patient!
```

## 🧪 **Run Specific Tests**

```bash
# Unit tests only (FIRST RUN: 30-120s, SUBSEQUENT: <5s)
go test ./internal/database/

# Unit tests with verbose output (see compilation progress)
go test -v ./internal/database/

# Show CGo compilation details (helps see it's not hanging)
go test -v -x ./internal/database/ 2>&1 | grep -i cgo

# Integration tests only
./scripts/test_sqldb.sh --integration-only

# Verbose output
./scripts/test_sqldb.sh --verbose

# Specific unit test
go test -run TestDatabaseCreation ./internal/database/

# With coverage
go test -cover ./internal/database/

# Pre-compile to watch CGo progress
go build -v ./internal/database/  # Watch CGo compilation happen
go test ./internal/database/       # Then tests run fast
```

## 🔍 **Manual Database Inspection**

```bash
# Connect to database in daemon container
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db

# Inside sqlite3 shell:
.schema deletions                   # View table structure
.indexes                            # List all indexes
PRAGMA journal_mode;                # Should show: wal
PRAGMA integrity_check;             # Should show: ok
SELECT COUNT(*) FROM deletions;     # Total records
SELECT * FROM deletions ORDER BY timestamp DESC LIMIT 10;  # Recent records
.quit                               # Exit
```

## 📊 **Quick Status Check**

```bash
# Check database health
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA integrity_check;"

# Record count
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT COUNT(*) FROM deletions;"

# Database size
docker compose exec storage-sage-daemon \
  stat -c "%s bytes" /var/lib/storage-sage/deletions.db

# WAL mode verification
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "PRAGMA journal_mode;"
```

## 🔧 **Common Operations**

### Backup
```bash
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  ".backup /var/lib/storage-sage/backup_$(date +%Y%m%d).db"
```

### Vacuum (Optimize)
```bash
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "VACUUM;"
```

### Delete Old Records (>90 days)
```bash
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db \
  "DELETE FROM deletions WHERE timestamp < datetime('now', '-90 days');"
```

## 📁 **Test Files Reference**

| File | Purpose |
|------|---------|
| [internal/database/database_test.go](internal/database/database_test.go) | 19 Go unit tests |
| [scripts/test_sqldb.sh](scripts/test_sqldb.sh) | Integration test script |
| [docs/DATABASE_TESTING.md](docs/DATABASE_TESTING.md) | Complete testing guide |
| [DATABASE_TEST_SUMMARY.md](DATABASE_TEST_SUMMARY.md) | Engineering analysis |

## ⚡ **Quick Troubleshooting**

### Tests Failing?

```bash
# 1. Ensure containers are running
docker compose ps

# 2. Check database volume exists
docker volume inspect storage-sage-db

# 3. Check database file permissions
docker compose exec storage-sage-daemon ls -la /var/lib/storage-sage/

# 4. Verify WAL mode
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA journal_mode;"
```

### Database Locked?

```bash
# Enable WAL mode (if not already)
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA journal_mode=WAL;"
```

### Database Corrupted?

```bash
# 1. Check integrity
docker compose exec storage-sage-daemon \
  sqlite3 /var/lib/storage-sage/deletions.db "PRAGMA integrity_check;"

# 2. If corrupted, restore from backup (see docs/DATABASE_TESTING.md)
```

## 📖 **Full Documentation**

For comprehensive testing procedures, architecture details, and troubleshooting:
- Read [docs/DATABASE_TESTING.md](docs/DATABASE_TESTING.md)
- Read [DATABASE_TEST_SUMMARY.md](DATABASE_TEST_SUMMARY.md)
