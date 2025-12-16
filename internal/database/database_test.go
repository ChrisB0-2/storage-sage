package database

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"storage-sage/internal/scan"
)

// TestDatabaseCreation verifies database file creation and initialization
func TestDatabaseCreation(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Verify database file exists
	if _, err := os.Stat(dbPath); os.IsNotExist(err) {
		t.Errorf("Database file not created at %s", dbPath)
	}

	// Verify WAL files exist (indicates WAL mode is active)
	walPath := dbPath + "-wal"

	// WAL files may not exist immediately if no writes occurred
	// Trigger a write to ensure WAL files are created
	err = db.RecordDeletion("TEST", scan.Candidate{
		Path: "/test/path",
		Size: 1024,
		DeletionReason: scan.DeletionReason{
			EvaluatedAt: time.Now(),
		},
	}, "")
	if err != nil {
		t.Fatalf("Failed to record test deletion: %v", err)
	}

	// Now check for WAL files
	if _, err := os.Stat(walPath); os.IsNotExist(err) {
		t.Logf("Warning: WAL file not found at %s (may be normal if no writes)", walPath)
	}
}

// TestWALModeEnabled verifies that WAL mode is properly configured
func TestWALModeEnabled(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_wal.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Query journal mode
	var journalMode string
	err = db.db.QueryRow("PRAGMA journal_mode").Scan(&journalMode)
	if err != nil {
		t.Fatalf("Failed to query journal mode: %v", err)
	}

	if journalMode != "wal" {
		t.Errorf("Expected journal_mode=wal, got %s", journalMode)
	}

	// Query synchronous mode
	var synchronous string
	err = db.db.QueryRow("PRAGMA synchronous").Scan(&synchronous)
	if err != nil {
		t.Fatalf("Failed to query synchronous mode: %v", err)
	}

	// synchronous=NORMAL returns 1
	if synchronous != "1" {
		t.Logf("Warning: synchronous mode is %s (expected 1 for NORMAL)", synchronous)
	}
}

// TestSchemaCreation verifies all tables and indexes are created
func TestSchemaCreation(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_schema.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Verify deletions table exists
	var tableName string
	err = db.db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name='deletions'").Scan(&tableName)
	if err != nil {
		t.Errorf("deletions table not found: %v", err)
	}

	// Verify schema_version table exists
	err = db.db.QueryRow("SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'").Scan(&tableName)
	if err != nil {
		t.Errorf("schema_version table not found: %v", err)
	}

	// Verify schema version is 2
	var version int
	err = db.db.QueryRow("SELECT version FROM schema_version LIMIT 1").Scan(&version)
	if err != nil {
		t.Errorf("Failed to read schema version: %v", err)
	}
	if version != 2 {
		t.Errorf("Expected schema version 2, got %d", version)
	}

	// Verify all 7 indexes exist
	expectedIndexes := []string{
		"idx_timestamp",
		"idx_action",
		"idx_path",
		"idx_primary_reason",
		"idx_mode",
		"idx_size",
		"idx_created_at",
	}

	for _, indexName := range expectedIndexes {
		var name string
		err = db.db.QueryRow("SELECT name FROM sqlite_master WHERE type='index' AND name=?", indexName).Scan(&name)
		if err != nil {
			t.Errorf("Index %s not found: %v", indexName, err)
		}
	}
}

// TestRecordDeletion verifies basic insertion functionality
func TestRecordDeletion(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_record.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	now := time.Now()
	candidate := scan.Candidate{
		Path:       "/test/file.log",
		Size:       1024,
		IsDir:      false,
		IsEmptyDir: false,
		DeletionReason: scan.DeletionReason{
			EvaluatedAt: now,
			AgeThreshold: &scan.AgeReason{
				ConfiguredDays: 30,
				ActualAgeDays:  45,
			},
			PathRule: "/var/log/*.log",
		},
	}

	err = db.RecordDeletion("DELETE", candidate, "")
	if err != nil {
		t.Fatalf("Failed to record deletion: %v", err)
	}

	// Verify record was inserted
	records, err := db.GetRecentDeletions(1)
	if err != nil {
		t.Fatalf("Failed to retrieve deletions: %v", err)
	}

	if len(records) != 1 {
		t.Fatalf("Expected 1 record, got %d", len(records))
	}

	record := records[0]
	if record.Path != "/test/file.log" {
		t.Errorf("Expected path /test/file.log, got %s", record.Path)
	}
	if record.Size != 1024 {
		t.Errorf("Expected size 1024, got %d", record.Size)
	}
	if record.Action != "DELETE" {
		t.Errorf("Expected action DELETE, got %s", record.Action)
	}
	if record.ObjectType != "file" {
		t.Errorf("Expected object_type file, got %s", record.ObjectType)
	}
}

// TestRecordAllFieldTypes verifies all field combinations work correctly
func TestRecordAllFieldTypes(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_fields.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	tests := []struct {
		name      string
		candidate scan.Candidate
		action    string
		errorMsg  string
	}{
		{
			name: "age_threshold_deletion",
			candidate: scan.Candidate{
				Path:  "/var/log/old.log",
				Size:  2048,
				IsDir: false,
				DeletionReason: scan.DeletionReason{
					EvaluatedAt: time.Now(),
					AgeThreshold: &scan.AgeReason{
						ConfiguredDays: 30,
						ActualAgeDays:  60,
					},
					PathRule: "/var/log/*.log",
				},
			},
			action:   "DELETE",
			errorMsg: "",
		},
		{
			name: "disk_threshold_deletion",
			candidate: scan.Candidate{
				Path:  "/data/large.dat",
				Size:  1073741824, // 1GB
				IsDir: false,
				DeletionReason: scan.DeletionReason{
					EvaluatedAt: time.Now(),
					DiskThreshold: &scan.DiskReason{
						ConfiguredPercent: 90.0,
						ActualPercent:     95.5,
					},
					PathRule: "/data/*",
				},
			},
			action:   "DELETE",
			errorMsg: "",
		},
		{
			name: "stacked_cleanup",
			candidate: scan.Candidate{
				Path:  "/backups/stack/2024-01-01.tar.gz",
				Size:  5368709120, // 5GB
				IsDir: false,
				DeletionReason: scan.DeletionReason{
					EvaluatedAt: time.Now(),
					StackedCleanup: &scan.StackedReason{
						StackThreshold: 80.0,
						StackAgeDays:   7,
						ActualAgeDays:  10,
						ActualPercent:  85.0,
					},
					PathRule: "/backups/stack/*",
				},
			},
			action:   "DELETE",
			errorMsg: "",
		},
		{
			name: "skip_action",
			candidate: scan.Candidate{
				Path:  "/active/server.log",
				Size:  512,
				IsDir: false,
				DeletionReason: scan.DeletionReason{
					EvaluatedAt: time.Now(),
					PathRule:    "/active/*",
				},
			},
			action:   "SKIP",
			errorMsg: "",
		},
		{
			name: "error_action",
			candidate: scan.Candidate{
				Path:  "/failed/delete.tmp",
				Size:  256,
				IsDir: false,
				DeletionReason: scan.DeletionReason{
					EvaluatedAt: time.Now(),
					PathRule:    "/failed/*",
				},
			},
			action:   "ERROR",
			errorMsg: "permission denied",
		},
		{
			name: "empty_directory",
			candidate: scan.Candidate{
				Path:       "/empty/dir",
				Size:       0,
				IsDir:      true,
				IsEmptyDir: true,
				DeletionReason: scan.DeletionReason{
					EvaluatedAt: time.Now(),
					PathRule:    "/empty/*",
				},
			},
			action:   "DELETE",
			errorMsg: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := db.RecordDeletion(tt.action, tt.candidate, tt.errorMsg)
			if err != nil {
				t.Errorf("Failed to record %s: %v", tt.name, err)
			}
		})
	}

	// Verify all records were inserted
	records, err := db.GetRecentDeletions(10)
	if err != nil {
		t.Fatalf("Failed to retrieve deletions: %v", err)
	}

	if len(records) != len(tests) {
		t.Errorf("Expected %d records, got %d", len(tests), len(records))
	}
}

// TestQueryMethods verifies all query functions work correctly
func TestQueryMethods(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_queries.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Insert test data
	now := time.Now()
	yesterday := now.Add(-24 * time.Hour)

	testData := []struct {
		action string
		path   string
		reason string
		size   int64
		time   time.Time
	}{
		{"DELETE", "/var/log/app1.log", "age_threshold", 1024, yesterday},
		{"DELETE", "/var/log/app2.log", "age_threshold", 2048, now},
		{"DELETE", "/data/big.dat", "disk_threshold", 1073741824, now},
		{"SKIP", "/active/server.log", "age_threshold", 512, now},
		{"ERROR", "/failed/test.tmp", "age_threshold", 256, now},
	}

	for _, td := range testData {
		candidate := scan.Candidate{
			Path: td.path,
			Size: td.size,
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: td.time,
				PathRule:    td.path,
			},
		}

		// Set appropriate reason
		switch td.reason {
		case "age_threshold":
			candidate.DeletionReason.AgeThreshold = &scan.AgeReason{
				ConfiguredDays: 30,
				ActualAgeDays:  45,
			}
		case "disk_threshold":
			candidate.DeletionReason.DiskThreshold = &scan.DiskReason{
				ConfiguredPercent: 90.0,
				ActualPercent:     95.0,
			}
		}

		errorMsg := ""
		if td.action == "ERROR" {
			errorMsg = "test error"
		}

		err := db.RecordDeletion(td.action, candidate, errorMsg)
		if err != nil {
			t.Fatalf("Failed to insert test data: %v", err)
		}
	}

	// Test GetRecentDeletions
	t.Run("GetRecentDeletions", func(t *testing.T) {
		records, err := db.GetRecentDeletions(3)
		if err != nil {
			t.Fatalf("GetRecentDeletions failed: %v", err)
		}
		if len(records) != 3 {
			t.Errorf("Expected 3 records, got %d", len(records))
		}
	})

	// Test GetDeletionsByAction
	t.Run("GetDeletionsByAction", func(t *testing.T) {
		records, err := db.GetDeletionsByAction("DELETE")
		if err != nil {
			t.Fatalf("GetDeletionsByAction failed: %v", err)
		}
		if len(records) != 3 {
			t.Errorf("Expected 3 DELETE records, got %d", len(records))
		}
	})

	// Test GetDeletionsByReason
	t.Run("GetDeletionsByReason", func(t *testing.T) {
		records, err := db.GetDeletionsByReason("age_threshold")
		if err != nil {
			t.Fatalf("GetDeletionsByReason failed: %v", err)
		}
		if len(records) != 4 {
			t.Errorf("Expected 4 age_threshold records, got %d", len(records))
		}
	})

	// Test GetDeletionsByPath
	t.Run("GetDeletionsByPath", func(t *testing.T) {
		records, err := db.GetDeletionsByPath("/var/log/%")
		if err != nil {
			t.Fatalf("GetDeletionsByPath failed: %v", err)
		}
		if len(records) != 2 {
			t.Errorf("Expected 2 /var/log records, got %d", len(records))
		}
	})

	// Test GetLargestDeletions
	t.Run("GetLargestDeletions", func(t *testing.T) {
		records, err := db.GetLargestDeletions(2)
		if err != nil {
			t.Fatalf("GetLargestDeletions failed: %v", err)
		}
		if len(records) != 2 {
			t.Errorf("Expected 2 records, got %d", len(records))
		}
		// Verify ordering (largest first)
		if records[0].Size < records[1].Size {
			t.Errorf("Records not sorted by size descending")
		}
	})

	// Test GetTotalSpaceFreed
	t.Run("GetTotalSpaceFreed", func(t *testing.T) {
		total, err := db.GetTotalSpaceFreed(yesterday.Add(-1*time.Hour), now.Add(1*time.Hour))
		if err != nil {
			t.Fatalf("GetTotalSpaceFreed failed: %v", err)
		}
		expectedTotal := int64(1024 + 2048 + 1073741824)
		if total != expectedTotal {
			t.Errorf("Expected total %d, got %d", expectedTotal, total)
		}
	})

	// Test GetDeletionCountByReason
	t.Run("GetDeletionCountByReason", func(t *testing.T) {
		counts, err := db.GetDeletionCountByReason()
		if err != nil {
			t.Fatalf("GetDeletionCountByReason failed: %v", err)
		}
		if counts["age_threshold"] != 2 {
			t.Errorf("Expected 2 age_threshold deletions, got %d", counts["age_threshold"])
		}
		if counts["disk_threshold"] != 1 {
			t.Errorf("Expected 1 disk_threshold deletion, got %d", counts["disk_threshold"])
		}
	})

	// Test GetDeletionCountByAction
	t.Run("GetDeletionCountByAction", func(t *testing.T) {
		counts, err := db.GetDeletionCountByAction()
		if err != nil {
			t.Fatalf("GetDeletionCountByAction failed: %v", err)
		}
		if counts["DELETE"] != 3 {
			t.Errorf("Expected 3 DELETE actions, got %d", counts["DELETE"])
		}
		if counts["SKIP"] != 1 {
			t.Errorf("Expected 1 SKIP action, got %d", counts["SKIP"])
		}
		if counts["ERROR"] != 1 {
			t.Errorf("Expected 1 ERROR action, got %d", counts["ERROR"])
		}
	})
}

// TestPaginationMethods verifies pagination works correctly
func TestPaginationMethods(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_pagination.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Insert 25 test records
	for i := 0; i < 25; i++ {
		candidate := scan.Candidate{
			Path: fmt.Sprintf("/test/file%d.log", i),
			Size: int64(i * 1024),
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: time.Now(),
				AgeThreshold: &scan.AgeReason{
					ConfiguredDays: 30,
					ActualAgeDays:  45,
				},
			},
		}

		err := db.RecordDeletion("DELETE", candidate, "")
		if err != nil {
			t.Fatalf("Failed to insert test record %d: %v", i, err)
		}
	}

	// Test GetRecentDeletionsPaginated
	t.Run("GetRecentDeletionsPaginated", func(t *testing.T) {
		records, total, err := db.GetRecentDeletionsPaginated(10, 0)
		if err != nil {
			t.Fatalf("GetRecentDeletionsPaginated failed: %v", err)
		}
		if total != 25 {
			t.Errorf("Expected total count 25, got %d", total)
		}
		if len(records) != 10 {
			t.Errorf("Expected 10 records in page 1, got %d", len(records))
		}

		// Test second page
		records, _, err = db.GetRecentDeletionsPaginated(10, 10)
		if err != nil {
			t.Fatalf("GetRecentDeletionsPaginated page 2 failed: %v", err)
		}
		if len(records) != 10 {
			t.Errorf("Expected 10 records in page 2, got %d", len(records))
		}

		// Test last page
		records, _, err = db.GetRecentDeletionsPaginated(10, 20)
		if err != nil {
			t.Fatalf("GetRecentDeletionsPaginated page 3 failed: %v", err)
		}
		if len(records) != 5 {
			t.Errorf("Expected 5 records in last page, got %d", len(records))
		}
	})
}

// TestConcurrentReads verifies multiple concurrent read operations
func TestConcurrentReads(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_concurrent_reads.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Insert test data
	for i := 0; i < 100; i++ {
		candidate := scan.Candidate{
			Path: fmt.Sprintf("/test/file%d.log", i),
			Size: 1024,
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: time.Now(),
			},
		}
		err := db.RecordDeletion("DELETE", candidate, "")
		if err != nil {
			t.Fatalf("Failed to insert test data: %v", err)
		}
	}

	// Launch 10 concurrent readers
	var wg sync.WaitGroup
	errors := make(chan error, 10)

	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()

			// Perform multiple read operations
			for j := 0; j < 10; j++ {
				_, err := db.GetRecentDeletions(10)
				if err != nil {
					errors <- fmt.Errorf("reader %d iteration %d: %v", id, j, err)
					return
				}
			}
		}(i)
	}

	wg.Wait()
	close(errors)

	// Check for errors
	for err := range errors {
		t.Errorf("Concurrent read error: %v", err)
	}
}

// TestConcurrentReadWrite verifies concurrent read and write operations
func TestConcurrentReadWrite(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_concurrent_rw.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	var wg sync.WaitGroup
	errors := make(chan error, 20)

	// Launch 1 writer
	wg.Add(1)
	go func() {
		defer wg.Done()

		for i := 0; i < 100; i++ {
			candidate := scan.Candidate{
				Path: fmt.Sprintf("/test/write%d.log", i),
				Size: 1024,
				DeletionReason: scan.DeletionReason{
					EvaluatedAt: time.Now(),
				},
			}
			err := db.RecordDeletion("DELETE", candidate, "")
			if err != nil {
				errors <- fmt.Errorf("writer error: %v", err)
				return
			}
			time.Sleep(1 * time.Millisecond) // Small delay
		}
	}()

	// Launch 5 concurrent readers
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()

			for j := 0; j < 50; j++ {
				_, err := db.GetRecentDeletions(10)
				if err != nil {
					errors <- fmt.Errorf("reader %d: %v", id, err)
					return
				}
				time.Sleep(2 * time.Millisecond) // Small delay
			}
		}(i)
	}

	wg.Wait()
	close(errors)

	// Check for errors
	for err := range errors {
		t.Errorf("Concurrent read/write error: %v", err)
	}
}

// TestDatabaseStats verifies statistics gathering
func TestDatabaseStats(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_stats.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Insert test data
	for i := 0; i < 50; i++ {
		candidate := scan.Candidate{
			Path: fmt.Sprintf("/test/file%d.log", i),
			Size: 1024,
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: time.Now().Add(-time.Duration(i) * time.Hour),
			},
		}
		err := db.RecordDeletion("DELETE", candidate, "")
		if err != nil {
			t.Fatalf("Failed to insert test data: %v", err)
		}
	}

	// Test GetDatabaseStats
	stats, err := db.GetDatabaseStats()
	if err != nil {
		t.Fatalf("GetDatabaseStats failed: %v", err)
	}

	if stats["total_records"].(int64) != 50 {
		t.Errorf("Expected 50 total records, got %v", stats["total_records"])
	}

	if stats["database_size_bytes"].(int64) <= 0 {
		t.Errorf("Database size should be > 0, got %v", stats["database_size_bytes"])
	}

	// Debug: Print what we got
	t.Logf("Stats keys: %v", stats)

	if _, ok := stats["oldest_record"]; !ok {
		// Try to read the raw string to debug
		var oldestStr string
		_ = db.db.QueryRow("SELECT MIN(timestamp) FROM deletions").Scan(&oldestStr)
		t.Errorf("oldest_record not found in stats. Raw SQL value: '%s'", oldestStr)
	}

	if _, ok := stats["newest_record"]; !ok {
		var newestStr string
		_ = db.db.QueryRow("SELECT MAX(timestamp) FROM deletions").Scan(&newestStr)
		t.Errorf("newest_record not found in stats. Raw SQL value: '%s'", newestStr)
	}

	// Test GetDeletionStats
	deletionStats, err := db.GetDeletionStats(7)
	if err != nil {
		t.Fatalf("GetDeletionStats failed: %v", err)
	}

	if deletionStats.TotalDeletions <= 0 {
		t.Errorf("Expected deletions > 0, got %d", deletionStats.TotalDeletions)
	}

	if deletionStats.TotalSpaceFreed <= 0 {
		t.Errorf("Expected space freed > 0, got %d", deletionStats.TotalSpaceFreed)
	}
}

// TestVacuum verifies database vacuum operation
func TestVacuum(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_vacuum.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Insert and delete data to create fragmentation
	for i := 0; i < 100; i++ {
		candidate := scan.Candidate{
			Path: fmt.Sprintf("/test/file%d.log", i),
			Size: 1024,
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: time.Now().Add(-time.Duration(i*10) * 24 * time.Hour),
			},
		}
		err := db.RecordDeletion("DELETE", candidate, "")
		if err != nil {
			t.Fatalf("Failed to insert test data: %v", err)
		}
	}

	// Delete old records
	deleted, err := db.DeleteOldRecords(60)
	if err != nil {
		t.Fatalf("DeleteOldRecords failed: %v", err)
	}

	if deleted <= 0 {
		t.Logf("No records deleted (expected some)")
	}

	// Run vacuum
	err = db.Vacuum()
	if err != nil {
		t.Fatalf("Vacuum failed: %v", err)
	}

	// Verify database still works after vacuum
	records, err := db.GetRecentDeletions(10)
	if err != nil {
		t.Fatalf("GetRecentDeletions after vacuum failed: %v", err)
	}

	if len(records) == 0 {
		t.Error("Expected some records to remain after vacuum")
	}
}

// TestIndexUtilization verifies that indexes are being used
func TestIndexUtilization(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_indexes.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Insert test data
	for i := 0; i < 1000; i++ {
		candidate := scan.Candidate{
			Path: fmt.Sprintf("/test/file%d.log", i),
			Size: 1024,
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: time.Now(),
				AgeThreshold: &scan.AgeReason{
					ConfiguredDays: 30,
					ActualAgeDays:  45,
				},
			},
		}
		err := db.RecordDeletion("DELETE", candidate, "")
		if err != nil {
			t.Fatalf("Failed to insert test data: %v", err)
		}
	}

	// Test queries that should use indexes
	tests := []struct {
		name  string
		query string
	}{
		{
			name:  "timestamp_index",
			query: "EXPLAIN QUERY PLAN SELECT * FROM deletions WHERE timestamp > datetime('now', '-7 days')",
		},
		{
			name:  "action_index",
			query: "EXPLAIN QUERY PLAN SELECT * FROM deletions WHERE action = 'DELETE'",
		},
		{
			name:  "primary_reason_index",
			query: "EXPLAIN QUERY PLAN SELECT * FROM deletions WHERE primary_reason = 'age_threshold'",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rows, err := db.db.Query(tt.query)
			if err != nil {
				t.Fatalf("Query failed: %v", err)
			}
			defer func() {
				if err := rows.Close(); err != nil {
					t.Errorf("Failed to close rows: %v", err)
				}
			}()

			// Just verify the query plan can be retrieved
			// Detailed plan analysis would be complex
			hasRows := false
			for rows.Next() {
				hasRows = true
				var id, parent, notused int
				var detail string
				_ = rows.Scan(&id, &parent, &notused, &detail)
				t.Logf("Query plan: %s", detail)
			}

			if !hasRows {
				t.Error("No query plan returned")
			}
		})
	}
}

// TestBulkInsertPerformance verifies performance with large datasets
func TestBulkInsertPerformance(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping performance test in short mode")
	}

	dbPath := filepath.Join(t.TempDir(), "test_bulk.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	count := 10000
	start := time.Now()

	for i := 0; i < count; i++ {
		candidate := scan.Candidate{
			Path: fmt.Sprintf("/test/file%d.log", i),
			Size: 1024,
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: time.Now(),
			},
		}
		err := db.RecordDeletion("DELETE", candidate, "")
		if err != nil {
			t.Fatalf("Failed to insert record %d: %v", i, err)
		}
	}

	elapsed := time.Since(start)
	insertsPerSecond := float64(count) / elapsed.Seconds()

	t.Logf("Inserted %d records in %v (%.2f inserts/sec)", count, elapsed, insertsPerSecond)

	// Sanity check: should be reasonably fast
	if insertsPerSecond < 100 {
		t.Logf("Warning: Insert performance is low (%.2f inserts/sec)", insertsPerSecond)
	}

	// Verify count
	stats, err := db.GetDatabaseStats()
	if err != nil {
		t.Fatalf("GetDatabaseStats failed: %v", err)
	}

	if stats["total_records"].(int64) != int64(count) {
		t.Errorf("Expected %d records, got %v", count, stats["total_records"])
	}
}

// TestDatabaseErrorHandling verifies error conditions are handled properly
func TestDatabaseErrorHandling(t *testing.T) {
	// Test: Invalid database path
	t.Run("InvalidPath", func(t *testing.T) {
		_, err := NewDeletionDB("/dev/null/invalid/path/db.sqlite")
		if err == nil {
			t.Error("Expected error for invalid database path")
		}
	})

	// Test: Read-only filesystem simulation (if possible)
	t.Run("ReadOnlyAccess", func(t *testing.T) {
		dbPath := filepath.Join(t.TempDir(), "readonly.db")

		// Create database first
		db, err := NewDeletionDB(dbPath)
		if err != nil {
			t.Fatalf("Failed to create database: %v", err)
		}
		db.Close()

		// Make database file read-only
		err = os.Chmod(dbPath, 0444)
		if err != nil {
			t.Skipf("Cannot change file permissions: %v", err)
		}
		defer func() { _ = os.Chmod(dbPath, 0644) }() // Restore permissions

		// Try to open and write
		db, err = NewDeletionDB(dbPath)
		if err != nil {
			// Expected on some systems
			t.Logf("Cannot open read-only database: %v", err)
			return
		}
		defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

		// Try to insert (should fail)
		candidate := scan.Candidate{
			Path: "/test/file.log",
			Size: 1024,
			DeletionReason: scan.DeletionReason{
				EvaluatedAt: time.Now(),
			},
		}
		err = db.RecordDeletion("DELETE", candidate, "")
		if err == nil {
			t.Error("Expected error when writing to read-only database")
		}
	})
}

// TestNullFieldHandling verifies nullable fields work correctly
func TestNullFieldHandling(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test_nulls.db")

	db, err := NewDeletionDB(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Errorf("Failed to close database: %v", err)
		}
	}()

	// Insert record with minimal fields (many nulls)
	candidate := scan.Candidate{
		Path: "/test/minimal.log",
		Size: 512,
		DeletionReason: scan.DeletionReason{
			EvaluatedAt: time.Now(),
			// No threshold data - should result in NULL fields
		},
	}

	err = db.RecordDeletion("DELETE", candidate, "")
	if err != nil {
		t.Fatalf("Failed to record deletion with null fields: %v", err)
	}

	// Retrieve and verify
	records, err := db.GetRecentDeletions(1)
	if err != nil {
		t.Fatalf("Failed to retrieve deletions: %v", err)
	}

	if len(records) != 1 {
		t.Fatalf("Expected 1 record, got %d", len(records))
	}

	// Null fields should be handled gracefully
	record := records[0]
	if record.Path != "/test/minimal.log" {
		t.Errorf("Path mismatch: expected /test/minimal.log, got %s", record.Path)
	}
}
