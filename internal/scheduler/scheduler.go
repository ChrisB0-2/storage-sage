package scheduler

import (
	"context"
	"errors"
	"log"
	"time"

	"storage-sage/internal/cleanup"
	"storage-sage/internal/config"
	"storage-sage/internal/database"
	"storage-sage/internal/disk"
	"storage-sage/internal/limiter"
	"storage-sage/internal/metrics"
	"storage-sage/internal/scan"
)

func RunOnce(ctx context.Context, cfg *config.Config, dryRun bool, logger *log.Logger) error {
	return RunOnceWithDB(ctx, cfg, dryRun, logger, nil)
}

func RunOnceWithDB(ctx context.Context, cfg *config.Config, dryRun bool, logger *log.Logger, db *database.DeletionDB) error {
	if logger == nil {
		logger = log.Default()
	}
	if cfg == nil {
		return errors.New("nil config")
	}

	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	// Initialize CPU limiter if configured
	var cpuLimiter *limiter.CPULimiter
	if cfg.ResourceLimits.MaxCPUPercent > 0 {
		cpuLimiter = limiter.NewCPULimiter(cfg.ResourceLimits.MaxCPUPercent)
	}

	start := time.Now()

	// Record cleanup run timestamp
	metrics.RecordCleanupRun()

	// Update free space metrics for all monitored paths
	updateFreeSpaceMetrics(cfg, logger)

	// Determine cleanup mode based on disk usage (Section 4)
	cleanupMode := determineCleanupMode(cfg, logger)
	metrics.SetCleanupMode(cleanupMode)
	logger.Printf("cleanup mode: %s", cleanupMode)

	// Throttle CPU during scan
	if cpuLimiter != nil {
		cpuLimiter.Throttle()
	}

	candidates, err := scan.Scan(cfg, start)
	if err != nil {
		metrics.ErrorsTotal.Inc()
		return err
	}

	// Throttle CPU during cleanup
	if cpuLimiter != nil {
		cpuLimiter.Throttle()
	}

	// Create cleaner with database
	cleaner := cleanup.NewCleaner(logger, nil, dryRun, db)
	count, freed, err := cleaner.CleanupWithConfig(cfg, candidates)
	if err != nil {
		metrics.ErrorsTotal.Inc()
		return err
	}

	elapsed := time.Since(start).Seconds()
	metrics.CleanupDuration.Observe(elapsed)

	logger.Printf("cycle complete: candidates=%d deleted=%d freed=%d bytes duration=%.3fs", len(candidates), count, freed, elapsed)
	return nil
}

func Run(ctx context.Context, cfg *config.Config, dryRun bool, logger *log.Logger) error {
	if logger == nil {
		logger = log.Default()
	}
	if cfg == nil {
		return errors.New("nil config")
	}

	if err := RunOnce(ctx, cfg, dryRun, logger); err != nil {
		return err
	}

	ticker := time.NewTicker(cfg.Interval())
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			logger.Println("scheduler shutting down")
			return ctx.Err()
		case <-ticker.C:
			if err := RunOnce(ctx, cfg, dryRun, logger); err != nil {
				logger.Printf("error running cycle: %v", err)
			}
		}
	}
}

// updateFreeSpaceMetrics updates free space percentage metrics for all paths
// Uses optimized parallel scanning and caching based on config
func updateFreeSpaceMetrics(cfg *config.Config, logger *log.Logger) {
	// Apply scan optimizations from config
	if cfg.ScanOptimizations.FastScanThreshold > 0 {
		disk.SetFastScanThreshold(int64(cfg.ScanOptimizations.FastScanThreshold))
	}
	if cfg.ScanOptimizations.CacheTTLMinutes > 0 {
		disk.SetCacheTTL(time.Duration(cfg.ScanOptimizations.CacheTTLMinutes) * time.Minute)
	}

	// Collect all paths to scan
	allPaths := make([]string, 0, len(cfg.ScanPaths)+len(cfg.Paths))
	allPaths = append(allPaths, cfg.ScanPaths...)
	for _, rule := range cfg.Paths {
		allPaths = append(allPaths, rule.Path)
	}

	// Use parallel scanning if enabled (default: auto-enabled)
	if cfg.ScanOptimizations.ParallelScans || len(allPaths) > 1 {
		results, err := disk.ScanPathsParallel(allPaths)
		if err != nil {
			logger.Printf("parallel scan encountered errors: %v", err)
		}

		// Update metrics from results
		for path, stats := range results {
			metrics.UpdateAllDiskMetrics(path, stats)
		}
	} else {
		// Sequential scan (fallback)
		for _, path := range allPaths {
			stats, err := disk.ScanPath(path)
			if err != nil {
				logger.Printf("failed to scan path %s: %v", path, err)
				continue
			}
			metrics.UpdateAllDiskMetrics(path, stats)
		}
	}
}

// determineCleanupMode determines the cleanup mode based on disk usage thresholds
// Section 4: Cleanup mode decision logic
// - AGE-BASED mode when free_space_percent >= max_free_percent
// - DISK-USAGE mode when free_space_percent < max_free_percent but >= stack_threshold
// - STACK mode when free_space_percent < stack_threshold
func determineCleanupMode(cfg *config.Config, logger *log.Logger) string {
	// Check all paths and determine the most critical mode
	mode := "AGE" // Default mode

	// Check scan_paths (use global thresholds if available)
	for _, path := range cfg.ScanPaths {
		usedPercent, _, _, err := disk.GetDiskUsage(path)
		if err != nil {
			logger.Printf("failed to get disk usage for %s: %v", path, err)
			continue
		}

		// Assume default thresholds if not set globally
		maxFreePercent := 90.0
		stackThreshold := 98.0

		if usedPercent >= stackThreshold {
			return "STACK" // Most critical - return immediately
		} else if usedPercent >= maxFreePercent {
			mode = "DISK" // Upgrade to DISK mode
		}
	}

	// Check path rules
	for _, rule := range cfg.Paths {
		usedPercent, _, _, err := disk.GetDiskUsage(rule.Path)
		if err != nil {
			logger.Printf("failed to get disk usage for %s: %v", rule.Path, err)
			continue
		}

		maxFreePercent := float64(rule.MaxFreePercent)
		stackThreshold := float64(rule.StackThreshold)

		if usedPercent >= stackThreshold {
			return "STACK" // Most critical - return immediately
		} else if usedPercent >= maxFreePercent {
			mode = "DISK" // Upgrade to DISK mode
		}
	}

	return mode
}
