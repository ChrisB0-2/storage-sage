package cleanup

import (
	"log"
	"os"
	"path/filepath"
	"testing"

	"storage-sage/internal/config"
	"storage-sage/internal/fsops"
	"storage-sage/internal/metrics"
	"storage-sage/internal/safety"
	"storage-sage/internal/scan"
)

func init() {
	// Initialize metrics once for all tests
	metrics.Init()
}

// TestDryRunNeverDeletes proves the dry-run contract:
// When dryRun=true, ZERO delete syscalls must occur
func TestDryRunNeverDeletes(t *testing.T) {
	tmpDir := t.TempDir()

	// Create config with allowed root
	cfg := &config.Config{
		ScanPaths: []string{tmpDir},
		CleanupOptions: config.CleanupOptions{
			Recursive:  true,
			DeleteDirs: true,
		},
	}

	// Create candidates for deletion
	candidates := []scan.Candidate{
		{
			Path:  filepath.Join(tmpDir, "file1.txt"),
			Size:  1024,
			IsDir: false,
		},
		{
			Path:       filepath.Join(tmpDir, "emptydir"),
			Size:       0,
			IsDir:      true,
			IsEmptyDir: true,
		},
		{
			Path:  filepath.Join(tmpDir, "fulldir"),
			Size:  2048,
			IsDir: true,
		},
	}

	// Create fake deleter to track calls
	fakeDeleter := &fsops.FakeDeleter{Calls: []string{}}

	// Create cleaner in DRY-RUN mode
	cleaner := NewCleaner(log.Default(), nil, true, nil) // dryRun=true
	cleaner.SetDeleter(fakeDeleter)
	cleaner.SetValidator(safety.NewValidator([]string{tmpDir}, nil))

	// Execute cleanup
	_, _, err := cleaner.CleanupWithConfig(cfg, candidates)
	if err != nil {
		t.Fatalf("CleanupWithConfig failed: %v", err)
	}

	// DRY-RUN CONTRACT: Assert ZERO delete calls occurred
	if len(fakeDeleter.Calls) != 0 {
		t.Errorf("DRY-RUN VIOLATION: Expected 0 delete calls, got %d: %v",
			len(fakeDeleter.Calls), fakeDeleter.Calls)
	}
}

// TestRealModeCallsDeleter proves that non-dry-run mode DOES call deleter
func TestRealModeCallsDeleter(t *testing.T) {
	tmpDir := t.TempDir()

	// Create actual files for realistic test
	file1 := filepath.Join(tmpDir, "file1.txt")
	if err := os.WriteFile(file1, []byte("test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	cfg := &config.Config{
		ScanPaths: []string{tmpDir},
		CleanupOptions: config.CleanupOptions{
			Recursive:  false,
			DeleteDirs: false,
		},
	}

	candidates := []scan.Candidate{
		{
			Path:  file1,
			Size:  4,
			IsDir: false,
		},
	}

	// Create fake deleter
	fakeDeleter := &fsops.FakeDeleter{Calls: []string{}}

	// Create cleaner in REAL mode (dryRun=false)
	cleaner := NewCleaner(log.Default(), nil, false, nil) // dryRun=false
	cleaner.SetDeleter(fakeDeleter)
	cleaner.SetValidator(safety.NewValidator([]string{tmpDir}, nil))

	// Execute cleanup
	count, _, err := cleaner.CleanupWithConfig(cfg, candidates)
	if err != nil {
		t.Fatalf("CleanupWithConfig failed: %v", err)
	}

	// Assert deleter was called
	if len(fakeDeleter.Calls) != 1 {
		t.Errorf("Expected 1 delete call, got %d: %v", len(fakeDeleter.Calls), fakeDeleter.Calls)
	}

	// Assert success count matches
	if count != 1 {
		t.Errorf("Expected 1 successful deletion, got %d", count)
	}

	// Assert the right file was targeted
	expectedCall := "rm:" + file1
	if len(fakeDeleter.Calls) > 0 && fakeDeleter.Calls[0] != expectedCall {
		t.Errorf("Expected call %s, got %s", expectedCall, fakeDeleter.Calls[0])
	}
}

// TestSafetyValidatorBlocksDeletion proves validator integration works
func TestSafetyValidatorBlocksDeletion(t *testing.T) {
	tmpDir := t.TempDir()

	cfg := &config.Config{
		ScanPaths: []string{tmpDir},
		CleanupOptions: config.CleanupOptions{
			Recursive:  true,
			DeleteDirs: true,
		},
	}

	// Try to delete /etc/passwd (protected path)
	candidates := []scan.Candidate{
		{
			Path:  "/etc/passwd",
			Size:  1024,
			IsDir: false,
		},
	}

	fakeDeleter := &fsops.FakeDeleter{Calls: []string{}}

	cleaner := NewCleaner(log.Default(), nil, false, nil) // Real mode
	cleaner.SetDeleter(fakeDeleter)
	cleaner.SetValidator(safety.NewValidator([]string{tmpDir}, nil))

	// Execute cleanup
	count, _, err := cleaner.CleanupWithConfig(cfg, candidates)
	if err != nil {
		t.Fatalf("CleanupWithConfig failed: %v", err)
	}

	// Assert validator blocked the deletion
	if len(fakeDeleter.Calls) != 0 {
		t.Errorf("SAFETY VIOLATION: Validator should have blocked protected path, but got %d calls: %v",
			len(fakeDeleter.Calls), fakeDeleter.Calls)
	}

	// Assert zero successful deletions
	if count != 0 {
		t.Errorf("Expected 0 successful deletions (blocked by validator), got %d", count)
	}
}
