package config

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

type PathRule struct {
	Path              string `yaml:"path" json:"path"`
	AgeOffDays        int    `yaml:"age_off_days" json:"age_off_days"`
	MinFreePercent    int    `yaml:"min_free_percent" json:"min_free_percent"`
	MaxFreePercent    int    `yaml:"max_free_percent" json:"max_free_percent"`       // Threshold to trigger cleanup (e.g., 90)
	TargetFreePercent int    `yaml:"target_free_percent" json:"target_free_percent"` // Target after cleanup (e.g., 80)
	Priority          int    `yaml:"priority" json:"priority"`                       // Lower number = higher priority (e.g., 1 = highest)
	StackThreshold    int    `yaml:"stack_threshold" json:"stack_threshold"`         // Percentage where stacked cleanup triggers (e.g., 98)
	StackAgeDays      int    `yaml:"stack_age_days" json:"stack_age_days"`           // Age threshold for stacked cleanup (e.g., 14)
}

type PrometheusCfg struct {
	Port int `yaml:"port" json:"port"`
}

type LoggingCfg struct {
	RotationDays int `yaml:"rotation_days" json:"rotation_days"` // Days to keep logs before rotation
}

type ResourceLimits struct {
	MaxCPUPercent float64 `yaml:"max_cpu_percent" json:"max_cpu_percent"` // Maximum CPU usage (e.g., 10.0)
}

type CleanupOptions struct {
	Recursive  bool `yaml:"recursive" json:"recursive"`     // Recursive deletion flag
	DeleteDirs bool `yaml:"delete_dirs" json:"delete_dirs"` // Allow directory deletion flag
}

type ScanOptimizations struct {
	FastScanThreshold int `yaml:"fast_scan_threshold" json:"fast_scan_threshold"` // File count threshold for du -sb mode (default: 1M)
	CacheTTLMinutes   int `yaml:"cache_ttl_minutes" json:"cache_ttl_minutes"`     // Cache TTL in minutes (default: 5)
	ParallelScans     bool `yaml:"parallel_scans" json:"parallel_scans"`           // Enable parallel path scanning (default: true)
	UseFastScan       bool `yaml:"use_fast_scan" json:"use_fast_scan"`             // Enable du -sb for large paths (default: true)
	UseCache          bool `yaml:"use_cache" json:"use_cache"`                     // Enable scan caching (default: true)
}

type WorkerPoolConfig struct {
	Enabled         bool `yaml:"enabled" json:"enabled"`                   // Enable worker pool for concurrent cleanup (default: true)
	Concurrency     int  `yaml:"concurrency" json:"concurrency"`           // Number of concurrent workers (default: 5, like beerus)
	BatchSize       int  `yaml:"batch_size" json:"batch_size"`             // Files per batch (default: 100)
	TimeoutSeconds  int  `yaml:"timeout_seconds" json:"timeout_seconds"`   // Timeout per batch in seconds (default: 30)
}

type Config struct {
	ScanPaths          []string           `yaml:"scan_paths" json:"scan_paths"`
	MinFreePercent     int                `yaml:"min_free_percent" json:"min_free_percent"`
	AgeOffDays         int                `yaml:"age_off_days" json:"age_off_days"`
	IntervalMinutes    int                `yaml:"interval_minutes" json:"interval_minutes"`
	Paths              []PathRule         `yaml:"paths" json:"paths"`
	Prometheus         PrometheusCfg      `yaml:"prometheus" json:"prometheus"`
	Logging            LoggingCfg         `yaml:"logging" json:"logging"`
	ResourceLimits     ResourceLimits     `yaml:"resource_limits" json:"resource_limits"`
	CleanupOptions     CleanupOptions     `yaml:"cleanup_options" json:"cleanup_options"`
	ScanOptimizations  ScanOptimizations  `yaml:"scan_optimizations" json:"scan_optimizations"`
	WorkerPool         WorkerPoolConfig   `yaml:"worker_pool" json:"worker_pool"`                 // Worker pool configuration
	NFSTimeout         int                `yaml:"nfs_timeout_seconds" json:"nfs_timeout_seconds"` // Timeout for NFS operations
	DatabasePath       string             `yaml:"database_path" json:"database_path"`             // Path to SQLite database for deletion history
}

var (
	errNoPaths         = errors.New("configuration must specify scan_paths or paths")
	errInvalidPath     = errors.New("path must be absolute")
	errNegativeAge     = errors.New("age_off_days cannot be negative")
	errInvalidInterval = errors.New("interval_minutes must be positive")
)

func Load(path string) (*Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open config: %w", err)
	}
	defer f.Close()

	cfg, err := decode(f)
	if err != nil {
		return nil, err
	}
	if err := cfg.validateAndDefault(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func decode(r io.Reader) (*Config, error) {
	cfg := &Config{}
	decoder := yaml.NewDecoder(r)
	if err := decoder.Decode(cfg); err != nil {
		return nil, fmt.Errorf("decode yaml: %w", err)
	}
	return cfg, nil
}

func (c *Config) validateAndDefault() error {
	if len(c.ScanPaths) == 0 && len(c.Paths) == 0 {
		return errNoPaths
	}

	if c.AgeOffDays < 0 {
		return errNegativeAge
	}

	if c.IntervalMinutes <= 0 {
		c.IntervalMinutes = 15
	}

	if c.Prometheus.Port == 0 {
		c.Prometheus.Port = 9090
	}

	// Set defaults for logging
	if c.Logging.RotationDays <= 0 {
		c.Logging.RotationDays = 30 // Default: keep logs for 30 days
	}

	// Set defaults for resource limits
	if c.ResourceLimits.MaxCPUPercent <= 0 {
		c.ResourceLimits.MaxCPUPercent = 10.0 // Default: 10% CPU limit
	}

	// Set defaults for cleanup options
	// Recursive defaults to true for backward compatibility
	// DeleteDirs defaults to false for safety

	// Set defaults for NFS timeout
	if c.NFSTimeout <= 0 {
		c.NFSTimeout = 5 // Default: 5 seconds timeout for NFS operations
	}

	// Set default database path
	if c.DatabasePath == "" {
		c.DatabasePath = "/var/lib/storage-sage/deletions.db"
	}

	// Set defaults for scan optimizations
	if c.ScanOptimizations.FastScanThreshold <= 0 {
		c.ScanOptimizations.FastScanThreshold = 1000000 // Default: 1M files
	}
	if c.ScanOptimizations.CacheTTLMinutes <= 0 {
		c.ScanOptimizations.CacheTTLMinutes = 5 // Default: 5 minutes
	}
	// Booleans default to false, so explicitly set defaults only if needed
	// For now, assume user wants optimizations enabled by default

	// Set defaults for worker pool (beerus-inspired)
	if c.WorkerPool.Concurrency <= 0 {
		c.WorkerPool.Concurrency = 5 // Default: 5 workers (like beerus)
	}
	if c.WorkerPool.BatchSize <= 0 {
		c.WorkerPool.BatchSize = 100 // Default: 100 files per batch
	}
	if c.WorkerPool.TimeoutSeconds <= 0 {
		c.WorkerPool.TimeoutSeconds = 30 // Default: 30 seconds per batch
	}
	// WorkerPool.Enabled defaults to false for backward compatibility
	// Users must explicitly enable to use worker pool

	// Set defaults for path rules
	for i := range c.Paths {
		if c.Paths[i].MaxFreePercent <= 0 {
			c.Paths[i].MaxFreePercent = 90 // Default: trigger at 90% usage
		}
		if c.Paths[i].TargetFreePercent <= 0 {
			c.Paths[i].TargetFreePercent = 80 // Default: target 80% usage
		}
		if c.Paths[i].Priority <= 0 {
			c.Paths[i].Priority = 100 // Default: lower priority
		}
		if c.Paths[i].StackThreshold <= 0 {
			c.Paths[i].StackThreshold = 98 // Default: stack cleanup at 98%
		}
		if c.Paths[i].StackAgeDays <= 0 {
			c.Paths[i].StackAgeDays = 14 // Default: 14 days for stacked cleanup
		}
	}

	cleaned := make([]string, 0, len(c.ScanPaths))
	for _, p := range c.ScanPaths {
		cp, err := cleanAbsolute(p)
		if err != nil {
			return err
		}
		cleaned = append(cleaned, cp)
	}
	c.ScanPaths = cleaned

	for i := range c.Paths {
		cp, err := cleanAbsolute(c.Paths[i].Path)
		if err != nil {
			return err
		}
		c.Paths[i].Path = cp
		if c.Paths[i].AgeOffDays < 0 {
			return fmt.Errorf("path %s: %w", c.Paths[i].Path, errNegativeAge)
		}
	}

	return nil
}

func cleanAbsolute(p string) (string, error) {
	if p == "" {
		return "", errInvalidPath
	}
	cp := filepath.Clean(p)
	if !filepath.IsAbs(cp) {
		return "", fmt.Errorf("%w: %s", errInvalidPath, p)
	}
	return cp, nil
}

func (c *Config) Interval() time.Duration {
	return time.Duration(c.IntervalMinutes) * time.Minute
}

func (c *Config) PrometheusAddress() string {
	return fmt.Sprintf(":%d", c.Prometheus.Port)
}
