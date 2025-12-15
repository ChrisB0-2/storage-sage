package logging

import (
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"storage-sage/internal/config"
)

const (
	logDir  = "/var/log/storage-sage"
	logFile = "cleanup.log"
)

// Logger wraps the standard logger with rotation support
type Logger struct {
	*log.Logger
}

// New creates a new logger with rotation support
func New() *log.Logger {
	return NewWithConfig(nil)
}

// NewWithConfig creates a new logger with configuration for rotation
func NewWithConfig(cfg *config.Config) *log.Logger {
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		log.Printf("failed to ensure log directory %s: %v", logDir, err)
	}

	filePath := filepath.Join(logDir, logFile)

	// Check if rotation is needed
	rotateDays := 30 // default
	if cfg != nil && cfg.Logging.RotationDays > 0 {
		rotateDays = cfg.Logging.RotationDays
	}

	// Rotate logs if needed
	rotateLogsIfNeeded(filePath, rotateDays)

	f, err := os.OpenFile(filePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		log.Printf("failed to open log file %s: %v", filePath, err)
		return log.New(os.Stdout, "", log.LstdFlags|log.Lmicroseconds)
	}

	mw := io.MultiWriter(os.Stdout, f)
	return log.New(mw, "", log.LstdFlags|log.Lmicroseconds)
}

// rotateLogsIfNeeded rotates log files older than the specified days
func rotateLogsIfNeeded(logPath string, rotationDays int) {
	info, err := os.Stat(logPath)
	if err != nil {
		// Log file doesn't exist yet, nothing to rotate
		return
	}

	// Check if log file is older than rotation days
	cutoffTime := time.Now().AddDate(0, 0, -rotationDays)
	if info.ModTime().Before(cutoffTime) {
		// Rotate: rename current log with timestamp
		timestamp := info.ModTime().Format("20060102-150405")
		rotatedPath := logPath + "." + timestamp

		if err := os.Rename(logPath, rotatedPath); err != nil {
			log.Printf("failed to rotate log file: %v", err)
			return
		}

		// Clean up old rotated logs
		cleanupOldLogs(logPath, rotationDays)
	}
}

// cleanupOldLogs removes log files older than rotation days
func cleanupOldLogs(logPath string, rotationDays int) {
	logDir := filepath.Dir(logPath)
	baseName := filepath.Base(logPath)

	entries, err := os.ReadDir(logDir)
	if err != nil {
		return
	}

	cutoffTime := time.Now().AddDate(0, 0, -rotationDays)

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		// Check if this is a rotated log file
		name := entry.Name()
		if !strings.HasPrefix(filepath.Base(name), filepath.Base(baseName)+".") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		// Delete if older than rotation days
		if info.ModTime().Before(cutoffTime) {
			fullPath := filepath.Join(logDir, name)
			if err := os.Remove(fullPath); err != nil {
				log.Printf("failed to remove old log file %s: %v", fullPath, err)
			}
		}
	}
}
