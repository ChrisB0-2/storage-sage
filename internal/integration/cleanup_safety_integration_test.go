package integration

import (
	"log"
	"os"
	"path/filepath"
	"testing"

	"storage-sage/internal/cleanup"
	"storage-sage/internal/config"
	"storage-sage/internal/metrics"
	"storage-sage/internal/safety"
	"storage-sage/internal/scan"
)

func init() {
	// Initialize metrics once for all integration tests
	metrics.Init()
}

// TestCleanupSafetyIntegration verifies complete safety contract with real filesystem
// This is the integration test required by the specification
func TestCleanupSafetyIntegration(t *testing.T) {
	// 1. Create temporary filesystem structure
	tmpRoot := t.TempDir()
	allowedDir := filepath.Join(tmpRoot, "allowed")
	protectedDir := filepath.Join(tmpRoot, "protected")

	if err := os.MkdirAll(allowedDir, 0755); err != nil {
		t.Fatalf("Failed to create allowed dir: %v", err)
	}
	if err := os.MkdirAll(protectedDir, 0755); err != nil {
		t.Fatalf("Failed to create protected dir: %v", err)
	}

	// Create junk files in allowed directory
	junkFile := filepath.Join(allowedDir, "junk.log")
	if err := os.WriteFile(junkFile, []byte("deletable content"), 0644); err != nil {
		t.Fatalf("Failed to create junk file: %v", err)
	}

	deletableDir := filepath.Join(allowedDir, "old_backups")
	if err := os.MkdirAll(deletableDir, 0755); err != nil {
		t.Fatalf("Failed to create deletable dir: %v", err)
	}
	deletableFile := filepath.Join(deletableDir, "old.tar.gz")
	if err := os.WriteFile(deletableFile, []byte("old backup"), 0644); err != nil {
		t.Fatalf("Failed to create deletable file in subdir: %v", err)
	}

	// Create protected file (must never be touched)
	protectedFile := filepath.Join(protectedDir, "keep.txt")
	if err := os.WriteFile(protectedFile, []byte("MUST KEEP"), 0644); err != nil {
		t.Fatalf("Failed to create protected file: %v", err)
	}

	// Create symlink inside allowed dir pointing to protected dir
	linkToProtected := filepath.Join(allowedDir, "link_to_protected")
	if err := os.Symlink(protectedFile, linkToProtected); err != nil {
		t.Fatalf("Failed to create symlink: %v", err)
	}

	// 2. Configure cleanup to only touch allowed directory
	cfg := &config.Config{
		ScanPaths: []string{allowedDir},
		CleanupOptions: config.CleanupOptions{
			Recursive:  true,
			DeleteDirs: true,
		},
	}

	// Create candidates for cleanup
	candidates := []scan.Candidate{
		{Path: junkFile, Size: 17, IsDir: false},
		{Path: deletableFile, Size: 10, IsDir: false},
		{Path: deletableDir, Size: 0, IsDir: true},
	}

	// 3a. DRY-RUN: Assert no deletions occur
	t.Run("DryRun_NoFilesystemChanges", func(t *testing.T) {
		cleaner := cleanup.NewCleaner(log.Default(), nil, true, nil) // dryRun=true
		cleaner.SetValidator(safety.NewValidator([]string{allowedDir}, nil))

		_, _, err := cleaner.CleanupWithConfig(cfg, candidates)
		if err != nil {
			t.Fatalf("DryRun cleanup failed: %v", err)
		}

		// Assert all files still exist
		if _, err := os.Stat(junkFile); os.IsNotExist(err) {
			t.Error("DRY-RUN VIOLATION: junk.log was deleted")
		}
		if _, err := os.Stat(deletableFile); os.IsNotExist(err) {
			t.Error("DRY-RUN VIOLATION: old.tar.gz was deleted")
		}
		if _, err := os.Stat(deletableDir); os.IsNotExist(err) {
			t.Error("DRY-RUN VIOLATION: old_backups was deleted")
		}
	})

	// 3b. EXECUTE: Assert only allowed deletions occur
	t.Run("RealMode_OnlyAllowedDeletes", func(t *testing.T) {
		// Recreate files if dry-run test ran first
		_ = os.WriteFile(junkFile, []byte("deletable content"), 0644)
		_ = os.WriteFile(deletableFile, []byte("old backup"), 0644)

		cleaner := cleanup.NewCleaner(log.Default(), nil, false, nil) // dryRun=false
		cleaner.SetValidator(safety.NewValidator([]string{allowedDir}, nil))

		count, _, err := cleaner.CleanupWithConfig(cfg, candidates)
		if err != nil {
			t.Fatalf("Real cleanup failed: %v", err)
		}

		// Assert deletions occurred
		if count != 3 {
			t.Errorf("Expected 3 deletions, got %d", count)
		}

		// Assert allowed files were deleted
		if _, err := os.Stat(junkFile); !os.IsNotExist(err) {
			t.Error("junk.log should have been deleted")
		}

		// Assert protected file still exists
		if _, err := os.Stat(protectedFile); os.IsNotExist(err) {
			t.Error("SAFETY VIOLATION: protected file was deleted")
		}
	})

	// 3c. SYMLINK ESCAPE: Assert symlink escapes are blocked
	t.Run("SymlinkEscape_Blocked", func(t *testing.T) {
		// Try to delete symlink that points outside allowed root
		symlinkCandidates := []scan.Candidate{
			{Path: linkToProtected, Size: 0, IsDir: false},
		}

		cleaner := cleanup.NewCleaner(log.Default(), nil, false, nil) // dryRun=false
		cleaner.SetValidator(safety.NewValidator([]string{allowedDir}, nil))

		count, _, err := cleaner.CleanupWithConfig(cfg, symlinkCandidates)
		if err != nil {
			t.Fatalf("Cleanup failed: %v", err)
		}

		// Validator should block the symlink escape
		if count != 0 {
			t.Errorf("SAFETY VIOLATION: Expected 0 deletions (symlink escape), got %d", count)
		}

		// Protected file must still exist
		if _, err := os.Stat(protectedFile); os.IsNotExist(err) {
			t.Error("CRITICAL SAFETY VIOLATION: protected file deleted via symlink escape")
		}
	})

	// 3d. OUTSIDE ALLOWED ROOT: Assert blocked
	t.Run("OutsideAllowedRoot_Blocked", func(t *testing.T) {
		outsideCandidates := []scan.Candidate{
			{Path: protectedFile, Size: 10, IsDir: false},
		}

		cleaner := cleanup.NewCleaner(log.Default(), nil, false, nil) // dryRun=false
		cleaner.SetValidator(safety.NewValidator([]string{allowedDir}, nil))

		count, _, err := cleaner.CleanupWithConfig(cfg, outsideCandidates)
		if err != nil {
			t.Fatalf("Cleanup failed: %v", err)
		}

		// Validator should block deletion outside allowed root
		if count != 0 {
			t.Errorf("SAFETY VIOLATION: Expected 0 deletions (outside root), got %d", count)
		}

		// Protected file must still exist
		if _, err := os.Stat(protectedFile); os.IsNotExist(err) {
			t.Error("CRITICAL SAFETY VIOLATION: file outside allowed root was deleted")
		}
	})

	// 4. PROTECTED PATHS: Verify system paths are never deleted
	t.Run("ProtectedPaths_Blocked", func(t *testing.T) {
		protectedPaths := []string{
			"/etc/passwd",
			"/bin/sh",
			"/usr/bin/id",
			"/boot/vmlinuz",
		}

		for _, path := range protectedPaths {
			validator := safety.NewValidator([]string{"/"}, nil)
			err := validator.ValidateDeleteTarget(path)
			if err != safety.ErrProtectedPath {
				t.Errorf("SAFETY VIOLATION: Protected path %s not blocked (err=%v)", path, err)
			}
		}
	})
}

// TestCleanupMetrics verifies metrics are recorded correctly
func TestCleanupMetrics(t *testing.T) {
	tmpDir := t.TempDir()

	// Create test file
	testFile := filepath.Join(tmpDir, "metric_test.txt")
	testData := []byte("test data for metrics")
	if err := os.WriteFile(testFile, testData, 0644); err != nil {
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
		{Path: testFile, Size: int64(len(testData)), IsDir: false},
	}

	cleaner := cleanup.NewCleaner(log.Default(), nil, false, nil)
	cleaner.SetValidator(safety.NewValidator([]string{tmpDir}, nil))

	count, freed, err := cleaner.CleanupWithConfig(cfg, candidates)
	if err != nil {
		t.Fatalf("Cleanup failed: %v", err)
	}

	// Verify metrics
	if count != 1 {
		t.Errorf("Expected 1 deletion, got %d", count)
	}
	if freed != int64(len(testData)) {
		t.Errorf("Expected %d bytes freed, got %d", len(testData), freed)
	}
}
