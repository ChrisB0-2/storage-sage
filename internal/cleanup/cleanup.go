package cleanup

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"storage-sage/internal/config"
	"storage-sage/internal/database"
	"storage-sage/internal/disk"
	"storage-sage/internal/metrics"
	"storage-sage/internal/scan"

	"github.com/prometheus/client_golang/prometheus"
)

// CleanupLogger interface for structured logging in cleanup
type CleanupLogger interface {
	Info(msg string, args ...interface{})
	Error(msg string, args ...interface{})
}

// cleanupStdLogger wraps standard log.Logger to implement CleanupLogger interface
type cleanupStdLogger struct {
	*log.Logger
}

func (l *cleanupStdLogger) Info(msg string, args ...interface{}) {
	l.logWithLevel("INFO", msg, args...)
}

func (l *cleanupStdLogger) Error(msg string, args ...interface{}) {
	l.logWithLevel("ERROR", msg, args...)
}

func (l *cleanupStdLogger) logWithLevel(level, msg string, args ...interface{}) {
	// Format key-value pairs
	var parts []interface{}
	parts = append(parts, fmt.Sprintf("[%s]", level), msg)
	parts = append(parts, args...)
	l.Logger.Println(parts...)
}

// Metrics interface for cleanup metrics
type Metrics interface {
	FilesProcessedTotal() prometheus.Counter
	SpaceFreedBytes() prometheus.Counter
	ErrorsTotal() prometheus.Counter
}

// cleanupMetrics wraps global metrics to implement Metrics interface
type cleanupMetrics struct{}

func (m *cleanupMetrics) FilesProcessedTotal() prometheus.Counter {
	return metrics.FilesDeletedTotal
}

func (m *cleanupMetrics) SpaceFreedBytes() prometheus.Counter {
	return metrics.BytesFreedTotal
}

func (m *cleanupMetrics) ErrorsTotal() prometheus.Counter {
	return metrics.ErrorsTotal
}

// Cleaner performs cleanup operations with structured logging
type Cleaner struct {
	logger  CleanupLogger
	metrics Metrics
	logFile *os.File // Optional file for structured logging
	dryRun  bool
	db      *database.DeletionDB // Database for recording deletion history
}

// NewCleaner creates a new Cleaner instance
func NewCleaner(logger *log.Logger, logFile *os.File, dryRun bool, db *database.DeletionDB) *Cleaner {
	cleanupLogger := &cleanupStdLogger{Logger: logger}
	if logger == nil {
		cleanupLogger.Logger = log.Default()
	}
	return &Cleaner{
		logger:  cleanupLogger,
		metrics: &cleanupMetrics{},
		logFile: logFile,
		dryRun:  dryRun,
		db:      db,
	}
}

func withinAllowed(path string, cfg *config.Config) bool {
	if cfg == nil {
		return false
	}
	cleaned := filepath.Clean(path)
	for _, root := range cfg.ScanPaths {
		if hasPathPrefix(cleaned, root) {
			return true
		}
	}
	for _, rule := range cfg.Paths {
		if hasPathPrefix(cleaned, rule.Path) {
			return true
		}
	}
	return false
}

func hasPathPrefix(path, root string) bool {
	root = filepath.Clean(root)
	if path == root {
		return true
	}
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return false
	}
	if rel == "." {
		return true
	}
	return !startsWithDotDot(rel)
}

func startsWithDotDot(rel string) bool {
	if rel == ".." {
		return true
	}
	prefix := ".." + string(os.PathSeparator)
	return strings.HasPrefix(rel, prefix)
}

// Cleanup removes candidates with proper error handling and logging
// This is the public API that maintains backward compatibility
func Cleanup(cfg *config.Config, candidates []scan.Candidate, dryRun bool, logger *log.Logger) (int, int64, error) {
	cleaner := NewCleaner(logger, nil, dryRun, nil) // Pass nil for db to maintain backward compatibility
	return cleaner.CleanupWithConfig(cfg, candidates)
}

// CleanupWithConfig performs cleanup with config validation and NFS checks
func (c *Cleaner) CleanupWithConfig(cfg *config.Config, candidates []scan.Candidate) (int, int64, error) {
	c.logger.Info("Starting cleanup", "total_candidates", len(candidates))

	var totalSpaceFreed int64
	successCount := 0
	errorCount := 0

	for _, cand := range candidates {
		// Check if path is within allowed paths
		if !withinAllowed(cand.Path, cfg) {
			c.logStructured("SKIP", cand.Path, "unsafe_path", 0, "")
			// Record skip to database
			if c.db != nil {
				c.db.RecordDeletion("SKIP", cand, "unsafe_path")
			}
			c.metrics.ErrorsTotal().Inc()
			errorCount++
			continue
		}

		// Check for stale NFS before attempting deletion
		if cfg.NFSTimeout > 0 {
			if disk.IsNFSStale(cand.Path, time.Duration(cfg.NFSTimeout)*time.Second) {
				c.logStructured("SKIP", cand.Path, "nfs_stale", cand.Size, "")
				// Record skip to database
				if c.db != nil {
					c.db.RecordDeletion("SKIP", cand, "nfs_stale")
				}
				c.metrics.ErrorsTotal().Inc()
				errorCount++
				continue
			}
		}

		var err error
		objectType := "file"
		deletionReason := ""
		if cand.DeletionReason.HasReason() {
			deletionReason = cand.DeletionReason.ToLogString()
		}

		if cand.IsDir {
			if cand.IsEmptyDir {
				objectType = "empty_directory"
				if !cfg.CleanupOptions.DeleteDirs {
					c.logStructured("SKIP", cand.Path, objectType, 0, deletionReason)
					// Record skip to database
					if c.db != nil {
						c.db.RecordDeletion("SKIP", cand, "delete_dirs_disabled")
					}
					continue
				}
				if c.dryRun {
					c.logger.Info("[DRY RUN] Would remove empty directory", "path", cand.Path)
				} else {
					err = os.Remove(cand.Path)
				}
			} else {
				objectType = "directory"
				if !cfg.CleanupOptions.DeleteDirs {
					c.logStructured("SKIP", cand.Path, objectType, 0, deletionReason)
					// Record skip to database
					if c.db != nil {
						c.db.RecordDeletion("SKIP", cand, "delete_dirs_disabled")
					}
					continue
				}
				if c.dryRun {
					c.logger.Info("[DRY RUN] Would remove directory recursively", "path", cand.Path)
				} else {
					if cfg.CleanupOptions.Recursive {
						err = os.RemoveAll(cand.Path)
					} else {
						err = os.Remove(cand.Path)
					}
				}
			}
		} else {
			if c.dryRun {
				c.logger.Info("[DRY RUN] Would delete file", "path", cand.Path, "size", cand.Size)
			} else {
				err = os.Remove(cand.Path)
			}
		}

		if err != nil {
			// Check if it's a stale NFS error during deletion
			if cfg.NFSTimeout > 0 && disk.IsNFSStale(cand.Path, time.Duration(cfg.NFSTimeout)*time.Second) {
				c.logStructured("SKIP", cand.Path, objectType, cand.Size, "nfs_stale_during_delete")
				// Record skip to database
				if c.db != nil {
					c.db.RecordDeletion("SKIP", cand, "nfs_stale_during_delete")
				}
				c.metrics.ErrorsTotal().Inc()
				errorCount++
				continue
			}

			// Don't count "file not found" errors as real errors - these are expected in race conditions
			// when multiple cleanup criteria match the same file and it gets deleted twice
			if os.IsNotExist(err) {
				c.logger.Info("File already deleted (race condition)", "path", cand.Path)
				// Log it but don't increment error counter or errorCount
				continue
			}

			c.logger.Error("Failed to delete", "path", cand.Path, "error", err)
			c.logStructured("ERROR", cand.Path, objectType, cand.Size, deletionReason)
			// Record error to database
			if c.db != nil {
				if dbErr := c.db.RecordDeletion("ERROR", cand, err.Error()); dbErr != nil {
					c.logger.Error("Failed to record error to database", "error", dbErr)
				}
			}
			c.metrics.ErrorsTotal().Inc()
			errorCount++
			continue
		}

		// Log successful deletion with reason
		action := "DELETE"
		if c.dryRun {
			action = "DRY_RUN"
		}

		c.logStructured(action, cand.Path, objectType, cand.Size, deletionReason)

		// Record to database
		if c.db != nil {
			if dbErr := c.db.RecordDeletion(action, cand, ""); dbErr != nil {
				c.logger.Error("Failed to record to database", "error", dbErr)
				// Don't fail cleanup if DB write fails
			}
		}

		totalSpaceFreed += cand.Size
		successCount++

		// Update Prometheus metrics
		c.metrics.FilesProcessedTotal().Inc()
		c.metrics.SpaceFreedBytes().Add(float64(cand.Size))

		// Record path-specific deletion metrics (Section 7.2)
		metrics.RecordPathDeletion(cand.Path, cand.Size)
	}

	c.logger.Info("Cleanup complete",
		"success", successCount,
		"errors", errorCount,
		"space_freed_bytes", totalSpaceFreed,
		"space_freed_mb", totalSpaceFreed/1024/1024,
	)

	return successCount, totalSpaceFreed, nil
}

// logStructured logs with structured format: timestamp, action, path, size, object type, deletion reason
func (c *Cleaner) logStructured(action, path, objectType string, size int64, deletionReason string) {
	logEntry := fmt.Sprintf("[%s] %s path=%s object=%s size=%d",
		time.Now().UTC().Format(time.RFC3339),
		action,
		path,
		objectType,
		size,
	)

	// Add deletion_reason if provided (NEW)
	if deletionReason != "" {
		// Escape quotes in reason string for proper log parsing
		escapedReason := strings.ReplaceAll(deletionReason, `"`, `\"`)
		logEntry += fmt.Sprintf(` deletion_reason="%s"`, escapedReason)
	}

	// Write to log file if available
	if c.logFile != nil {
		c.logFile.WriteString(logEntry + "\n")
		c.logFile.Sync() // Ensure immediate write to disk
	}

	// Also log to standard logger
	c.logger.Info(logEntry)
}
