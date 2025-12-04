package database

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"storage-sage/internal/scan"
)

// DeletionDB manages the SQLite database for deletion history
type DeletionDB struct {
	db *sql.DB
}

// DeletionRecord represents a single deletion event
type DeletionRecord struct {
	ID                      int64
	Timestamp               time.Time
	Action                  string
	Path                    string
	FileName                string
	ObjectType              string
	Size                    int64
	DeletionReason          string
	PrimaryReason           string
	Mode                    string  // AGE, DISK, or STACK
	Priority                *int    // Priority from path rule
	AgeDays                 *int    // Actual age in days
	AgeThresholdDays        *int
	ActualAgeDays           *int
	DiskThresholdPercent    *float64
	ActualDiskPercent       *float64
	StackedThresholdPercent *float64
	StackedAgeDays          *int
	PathRule                string
	ErrorMessage            string
	CreatedAt               time.Time
}

// NewDeletionDB creates a new database connection and initializes schema
func NewDeletionDB(dbPath string) (*DeletionDB, error) {
	// Create parent directory if it doesn't exist
	dir := filepath.Dir(dbPath)
	if dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, fmt.Errorf("failed to create database directory %s: %w", dir, err)
		}
	}

	// Open database connection with time parsing enabled
	// Note: SQLite will create the file if it doesn't exist
	// file: prefix with _loc=auto enables automatic DATETIME parsing
	db, err := sql.Open("sqlite3", "file:"+dbPath+"?_loc=auto")
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}
	defer func() {
		if err != nil {
			db.Close()
		}
	}()

	// Test connection by executing a simple query instead of Ping()
	// This ensures the database file is created if it doesn't exist
	if _, err = db.Exec("SELECT 1"); err != nil {
		return nil, fmt.Errorf("failed to initialize database (check permissions on %s): %w", dbPath, err)
	}

	// Enable WAL mode for better concurrency (multiple readers, one writer)
	if _, err = db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		return nil, fmt.Errorf("failed to enable WAL: %w", err)
	}

	// Optimize for write performance
	if _, err = db.Exec("PRAGMA synchronous=NORMAL"); err != nil {
		return nil, fmt.Errorf("failed to set synchronous mode: %w", err)
	}

	ddb := &DeletionDB{db: db}
	if err = ddb.initSchema(); err != nil {
		return nil, err
	}

	// Clear the deferred error handler since we succeeded
	err = nil
	return ddb, nil
}

// initSchema creates tables and indexes if they don't exist
func (d *DeletionDB) initSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS deletions (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp DATETIME NOT NULL,
		action TEXT NOT NULL,
		path TEXT NOT NULL,
		file_name TEXT,
		object_type TEXT NOT NULL,
		size INTEGER NOT NULL,

		deletion_reason TEXT,
		primary_reason TEXT,
		mode TEXT,
		priority INTEGER,
		age_days INTEGER,

		age_threshold_days INTEGER,
		actual_age_days INTEGER,
		disk_threshold_percent REAL,
		actual_disk_percent REAL,
		stacked_threshold_percent REAL,
		stacked_age_days INTEGER,

		path_rule TEXT,
		error_message TEXT,

		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_timestamp ON deletions(timestamp);
	CREATE INDEX IF NOT EXISTS idx_action ON deletions(action);
	CREATE INDEX IF NOT EXISTS idx_path ON deletions(path);
	CREATE INDEX IF NOT EXISTS idx_primary_reason ON deletions(primary_reason);
	CREATE INDEX IF NOT EXISTS idx_mode ON deletions(mode);
	CREATE INDEX IF NOT EXISTS idx_size ON deletions(size);
	CREATE INDEX IF NOT EXISTS idx_created_at ON deletions(created_at);

	-- Metadata table for schema versioning
	CREATE TABLE IF NOT EXISTS schema_version (
		version INTEGER PRIMARY KEY,
		applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	INSERT OR IGNORE INTO schema_version (version) VALUES (2);
	`

	_, err := d.db.Exec(schema)
	return err
}

// RecordDeletion inserts a deletion event into the database
func (d *DeletionDB) RecordDeletion(
	action string,
	candidate scan.Candidate,
	errorMsg string,
) error {
	reason := candidate.DeletionReason

	var ageThresholdDays, actualAgeDays, stackedAgeDays, ageDays *int
	var diskThresholdPercent, actualDiskPercent, stackedThresholdPercent *float64
	var priority *int

	// Extract structured reason data
	if reason.AgeThreshold != nil {
		ageThresholdDays = &reason.AgeThreshold.ConfiguredDays
		actualAgeDays = &reason.AgeThreshold.ActualAgeDays
		ageDays = &reason.AgeThreshold.ActualAgeDays
	}

	if reason.DiskThreshold != nil {
		diskThresholdPercent = &reason.DiskThreshold.ConfiguredPercent
		actualDiskPercent = &reason.DiskThreshold.ActualPercent
	}

	if reason.StackedCleanup != nil {
		stackedThresholdPercent = &reason.StackedCleanup.StackThreshold
		stackedAgeDays = &reason.StackedCleanup.StackAgeDays
		ageDays = &reason.StackedCleanup.ActualAgeDays
	}

	// Determine cleanup mode based on primary reason
	mode := determineMode(reason.GetPrimaryReason())

	query := `
	INSERT INTO deletions (
		timestamp, action, path, file_name, object_type, size,
		deletion_reason, primary_reason, mode, priority, age_days,
		age_threshold_days, actual_age_days,
		disk_threshold_percent, actual_disk_percent,
		stacked_threshold_percent, stacked_age_days,
		path_rule, error_message
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`

	_, err := d.db.Exec(
		query,
		reason.EvaluatedAt,
		action,
		candidate.Path,
		filepath.Base(candidate.Path),
		objectType(candidate),
		candidate.Size,
		reason.ToLogString(),
		reason.GetPrimaryReason(),
		mode,
		priority,
		ageDays,
		ageThresholdDays,
		actualAgeDays,
		diskThresholdPercent,
		actualDiskPercent,
		stackedThresholdPercent,
		stackedAgeDays,
		reason.PathRule,
		errorMsg,
	)

	return err
}

// determineMode maps primary reason to cleanup mode
func determineMode(primaryReason string) string {
	switch primaryReason {
	case "stacked_cleanup":
		return "STACK"
	case "disk_threshold", "combined":
		return "DISK"
	case "age_threshold":
		return "AGE"
	default:
		return "UNKNOWN"
	}
}

// objectType determines the object type string
func objectType(c scan.Candidate) string {
	if c.IsEmptyDir {
		return "empty_directory"
	}
	if c.IsDir {
		return "directory"
	}
	return "file"
}

// Close closes the database connection
func (d *DeletionDB) Close() error {
	return d.db.Close()
}

// Vacuum optimizes the database (run periodically)
func (d *DeletionDB) Vacuum() error {
	_, err := d.db.Exec("VACUUM")
	return err
}

// GetDatabaseStats returns database statistics
func (d *DeletionDB) GetDatabaseStats() (map[string]interface{}, error) {
	stats := make(map[string]interface{})

	// Total records
	var totalRecords int64
	err := d.db.QueryRow("SELECT COUNT(*) FROM deletions").Scan(&totalRecords)
	if err != nil {
		return nil, err
	}
	stats["total_records"] = totalRecords

	// Database size
	var pageCount, pageSize int64
	err = d.db.QueryRow("PRAGMA page_count").Scan(&pageCount)
	if err != nil {
		return nil, err
	}
	err = d.db.QueryRow("PRAGMA page_size").Scan(&pageSize)
	if err != nil {
		return nil, err
	}
	stats["database_size_bytes"] = pageCount * pageSize

	// Date range
	var oldestDateStr, newestDateStr sql.NullString
	err = d.db.QueryRow("SELECT MIN(timestamp), MAX(timestamp) FROM deletions").Scan(&oldestDateStr, &newestDateStr)
	if err != nil && err != sql.ErrNoRows {
		return nil, err
	}
	if oldestDateStr.Valid && oldestDateStr.String != "" {
		// SQLite stores time.Time as: "2025-11-19 23:01:56.489344855-05:00"
		// Format: "2006-01-02 15:04:05.999999999-07:00"
		if t, err := time.Parse("2006-01-02 15:04:05.999999999-07:00", oldestDateStr.String); err == nil {
			stats["oldest_record"] = t
		} else if t, err := time.Parse("2006-01-02 15:04:05-07:00", oldestDateStr.String); err == nil {
			stats["oldest_record"] = t
		} else if t, err := time.Parse(time.RFC3339Nano, oldestDateStr.String); err == nil {
			stats["oldest_record"] = t
		} else if t, err := time.Parse("2006-01-02 15:04:05", oldestDateStr.String); err == nil {
			stats["oldest_record"] = t
		}
	}
	if newestDateStr.Valid && newestDateStr.String != "" {
		// Try same formats for newest
		if t, err := time.Parse("2006-01-02 15:04:05.999999999-07:00", newestDateStr.String); err == nil {
			stats["newest_record"] = t
		} else if t, err := time.Parse("2006-01-02 15:04:05-07:00", newestDateStr.String); err == nil {
			stats["newest_record"] = t
		} else if t, err := time.Parse(time.RFC3339Nano, newestDateStr.String); err == nil {
			stats["newest_record"] = t
		} else if t, err := time.Parse("2006-01-02 15:04:05", newestDateStr.String); err == nil {
			stats["newest_record"] = t
		}
	}

	return stats, nil
}

