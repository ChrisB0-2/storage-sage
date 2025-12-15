package scan

import (
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"time"

	"storage-sage/internal/config"
	"storage-sage/internal/disk"
)

// Logger interface for structured logging
type Logger interface {
	Info(msg string, args ...interface{})
	Warn(msg string, args ...interface{})
	Debug(msg string, args ...interface{})
}

// stdLogger wraps standard log.Logger to implement Logger interface
type stdLogger struct {
	*log.Logger
}

func (l *stdLogger) Info(msg string, args ...interface{}) {
	l.logWithLevel("INFO", msg, args...)
}

func (l *stdLogger) Warn(msg string, args ...interface{}) {
	l.logWithLevel("WARN", msg, args...)
}

func (l *stdLogger) Debug(msg string, args ...interface{}) {
	l.logWithLevel("DEBUG", msg, args...)
}

func (l *stdLogger) logWithLevel(level, msg string, args ...interface{}) {
	// Format key-value pairs
	var parts []interface{}
	parts = append(parts, fmt.Sprintf("[%s]", level), msg)
	parts = append(parts, args...)
	l.Logger.Println(parts...)
}

// Scanner performs file system scans with deletion reason tracking
type Scanner struct {
	logger Logger
}

// NewScanner creates a new Scanner with the given logger
func NewScanner(logger *log.Logger) *Scanner {
	if logger == nil {
		logger = log.Default()
	}
	return &Scanner{
		logger: &stdLogger{Logger: logger},
	}
}

type Candidate struct {
	Path           string
	Size           int64
	ModTime        time.Time
	IsDir          bool
	IsEmptyDir     bool
	DeletionReason DeletionReason // NEW: Why this file was selected
}

type PathScanResult struct {
	Path          string
	Rule          *config.PathRule
	FreePercent   float64
	Candidates    []Candidate
	NeedsCleanup  bool
	CleanupReason string
	TargetBytes   int64 // Bytes to free to reach target
}

var errNoPaths = errors.New("no paths to scan")

// Scan performs a comprehensive scan considering age, disk usage, and priorities
func Scan(cfg *config.Config, now time.Time) ([]Candidate, error) {
	return ScanWithLogger(cfg, now, nil)
}

// ScanWithLogger performs a comprehensive scan with a custom logger
func ScanWithLogger(cfg *config.Config, now time.Time, logger *log.Logger) ([]Candidate, error) {
	if cfg == nil {
		return nil, errNoPaths
	}

	scanner := NewScanner(logger)

	// Get all paths with their rules and priorities
	pathResults := getPathResults(cfg, now)

	// Sort by priority (lower number = higher priority)
	sort.Slice(pathResults, func(i, j int) bool {
		return pathResults[i].Rule.Priority < pathResults[j].Rule.Priority
	})

	allCandidates := make([]Candidate, 0)

	// Process each path in priority order
	for _, pathResult := range pathResults {
		// Check for stale NFS
		if cfg.NFSTimeout > 0 {
			if disk.IsNFSStale(pathResult.Path, time.Duration(cfg.NFSTimeout)*time.Second) {
				// Skip stale NFS paths - log but don't fail
				continue
			}
		}

		// Calculate disk usage percentage (used, not free)
		diskUsage := 100.0 - pathResult.FreePercent

		candidates, err := scanner.scanPath(pathResult.Rule, diskUsage)
		if err != nil {
			// Log error but continue with other paths
			scanner.logger.Warn("Failed to scan path", "path", pathResult.Path, "error", err)
			continue
		}
		allCandidates = append(allCandidates, candidates...)
	}

	// Sort candidates by modification time (oldest first) for efficient cleanup
	sort.Slice(allCandidates, func(i, j int) bool {
		return allCandidates[i].ModTime.Before(allCandidates[j].ModTime)
	})

	return allCandidates, nil
}

// getPathResults analyzes all paths and determines cleanup needs
func getPathResults(cfg *config.Config, now time.Time) []PathScanResult {
	results := make([]PathScanResult, 0)

	// Create a map to track paths that have specific configs
	// This prevents duplicate paths and ensures specific configs override defaults
	pathMap := make(map[string]bool)

	// Process paths with rules first (specific configs take precedence)
	for i := range cfg.Paths {
		path := cfg.Paths[i].Path
		pathMap[path] = true
		results = append(results, analyzePath(&cfg.Paths[i], cfg, now))
	}

	// Process scan_paths (legacy format)
	// Skip paths that already have specific configs in paths:
	for _, path := range cfg.ScanPaths {
		// Skip if this path already has a specific config
		if pathMap[path] {
			continue
		}

		rule := &config.PathRule{
			Path:              path,
			AgeOffDays:        cfg.AgeOffDays,
			MinFreePercent:    cfg.MinFreePercent,
			MaxFreePercent:    90,  // Default
			TargetFreePercent: 80,  // Default
			Priority:          100, // Default lower priority
			StackThreshold:    98,
			StackAgeDays:      14,
		}
		results = append(results, analyzePath(rule, cfg, now))
	}

	return results
}

// getExcludePatterns returns exclude patterns for a rule (empty slice if not configured)
func getExcludePatterns(rule *config.PathRule) []string {
	// ExcludePatterns is not currently in PathRule, return empty slice
	// This can be extended when ExcludePatterns is added to PathRule
	return []string{}
}

// evaluateDeletionReason determines why a file was selected for deletion
func (s *Scanner) evaluateDeletionReason(
	rule *config.PathRule,
	ageInDays int,
	diskUsage float64,
	fileInfo os.FileInfo,
) DeletionReason {
	reason := DeletionReason{
		PathRule:    rule.Path,
		EvaluatedAt: time.Now(),
	}

	// Priority 1: Stacked cleanup (emergency mode - disk critically full + old files)
	// This is the most urgent condition
	if diskUsage >= float64(rule.StackThreshold) && ageInDays >= rule.StackAgeDays {
		reason.StackedCleanup = &StackedReason{
			StackThreshold: float64(rule.StackThreshold),
			StackAgeDays:   rule.StackAgeDays,
			ActualPercent:  diskUsage,
			ActualAgeDays:  ageInDays,
		}
	}

	// Priority 2: Disk threshold (urgent - disk too full)
	// Files are candidates because disk usage exceeded threshold
	if diskUsage >= float64(rule.MaxFreePercent) {
		reason.DiskThreshold = &DiskReason{
			ConfiguredPercent: float64(rule.MaxFreePercent),
			ActualPercent:     diskUsage,
		}
	}

	// Priority 3: Age threshold (baseline cleanup)
	// Files are candidates because they're too old
	if rule.AgeOffDays > 0 && ageInDays >= rule.AgeOffDays {
		reason.AgeThreshold = &AgeReason{
			ConfiguredDays: rule.AgeOffDays,
			ActualAgeDays:  ageInDays,
		}
	}

	return reason
}

// markEmptyDirectories marks directories as empty if they contain no files
func (s *Scanner) markEmptyDirectories(candidates []Candidate) []Candidate {
	// Create a map to track which directories are candidates
	dirMap := make(map[string]*Candidate)
	for i := range candidates {
		if candidates[i].IsDir {
			dirMap[candidates[i].Path] = &candidates[i]
		}
	}

	// Check each directory candidate to see if it's empty
	for i := range candidates {
		if candidates[i].IsDir {
			entries, err := os.ReadDir(candidates[i].Path)
			if err != nil {
				// If we can't read the directory, assume it's not empty
				candidates[i].IsEmptyDir = false
				continue
			}
			// Directory is empty if it has no entries
			candidates[i].IsEmptyDir = len(entries) == 0
		}
	}

	return candidates
}

// analyzePath determines if a path needs cleanup and why
func analyzePath(rule *config.PathRule, cfg *config.Config, now time.Time) PathScanResult {
	result := PathScanResult{
		Path: rule.Path,
		Rule: rule,
	}

	// Get current disk usage
	freePercent, _, totalBytes, err := disk.GetDiskUsage(rule.Path)
	if err != nil {
		// If we can't get disk usage, skip this path
		return result
	}
	result.FreePercent = freePercent
	usedPercent := 100.0 - freePercent

	// Check if we need cleanup based on disk usage
	if usedPercent >= float64(rule.MaxFreePercent) {
		result.NeedsCleanup = true
		result.CleanupReason = "disk_usage_threshold"
		// Calculate target bytes to free
		targetUsedPercent := float64(rule.TargetFreePercent)
		targetUsedBytes := (targetUsedPercent / 100.0) * float64(totalBytes)
		currentUsedBytes := ((100.0 - freePercent) / 100.0) * float64(totalBytes)
		result.TargetBytes = int64(currentUsedBytes - targetUsedBytes)
	}

	// Check for stacked cleanup (high usage + age threshold)
	if usedPercent >= float64(rule.StackThreshold) {
		result.NeedsCleanup = true
		if result.CleanupReason == "" {
			result.CleanupReason = "stacked_cleanup"
		} else {
			result.CleanupReason = "stacked_cleanup+" + result.CleanupReason
		}
	}

	return result
}

// scanPath scans a single path for candidates based on rules
func (s *Scanner) scanPath(rule *config.PathRule, diskUsage float64) ([]Candidate, error) {
	var candidates []Candidate

	// Determine which scans are active based on config and disk state
	needsAgeScan := rule.AgeOffDays > 0
	needsDiskScan := diskUsage >= float64(rule.MaxFreePercent)
	isStackedActive := diskUsage >= float64(rule.StackThreshold)

	// If no conditions are met, skip scanning this path entirely
	if !needsAgeScan && !needsDiskScan && !isStackedActive {
		s.logger.Info("Skipping path - no cleanup conditions met",
			"path", rule.Path,
			"disk_usage", diskUsage,
		)
		return candidates, nil
	}

	s.logger.Info("Starting path scan",
		"path", rule.Path,
		"age_scan", needsAgeScan,
		"disk_scan", needsDiskScan,
		"stacked_active", isStackedActive,
		"disk_usage", diskUsage,
	)

	excludePatterns := getExcludePatterns(rule)

	err := filepath.Walk(rule.Path, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			// Log and continue on permission errors
			if os.IsPermission(err) {
				s.logger.Warn("Permission denied", "path", path)
				return nil
			}
			return err
		}

		// Skip the root directory itself
		if path == rule.Path {
			return nil
		}

		// Skip excluded patterns
		for _, pattern := range excludePatterns {
			matched, err := filepath.Match(pattern, filepath.Base(path))
			if err != nil {
				s.logger.Warn("Invalid exclude pattern", "pattern", pattern, "error", err)
				continue
			}
			if matched {
				if info.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}
		}

		// Calculate file age (only if needed by any condition)
		var ageInDays int
		if needsAgeScan || isStackedActive {
			ageInDays = int(time.Since(info.ModTime()).Hours() / 24)
		}

		// Evaluate deletion reasons for this file/directory
		reason := s.evaluateDeletionReason(rule, ageInDays, diskUsage, info)

		// Only add as candidate if at least one reason applies
		if reason.HasReason() {
			candidate := Candidate{
				Path:           path,
				Size:           info.Size(),
				ModTime:        info.ModTime(),
				IsDir:          info.IsDir(),
				IsEmptyDir:     false, // Will be determined later if it's a directory
				DeletionReason: reason,
			}

			candidates = append(candidates, candidate)

			s.logger.Debug("File selected for deletion",
				"path", path,
				"size", info.Size(),
				"age_days", ageInDays,
				"reason", reason.ToLogString(),
			)
		}

		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to scan path %s: %w", rule.Path, err)
	}

	// Check for empty directories
	candidates = s.markEmptyDirectories(candidates)

	s.logger.Info("Path scan complete",
		"path", rule.Path,
		"candidates_found", len(candidates),
	)

	return candidates, nil
}

