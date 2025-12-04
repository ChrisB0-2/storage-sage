package disk

import (
	"fmt"
	"io/fs"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// PathStats contains detailed statistics about a filesystem path
type PathStats struct {
	UsedBytes  int64 // Total bytes used by files in this path
	FileCount  int64 // Total number of regular files
	FreeBytes  int64 // Free space available on the filesystem
	TotalBytes int64 // Total capacity of the filesystem
}

// ScanCache stores previous scan results for incremental updates
type ScanCache struct {
	mu    sync.RWMutex
	cache map[string]*cachedScan
}

type cachedScan struct {
	stats     *PathStats
	timestamp time.Time
	fileCount int64 // Used to detect if incremental scan is worth it
}

var (
	globalScanCache = &ScanCache{
		cache: make(map[string]*cachedScan),
	}

	// FastScanThreshold: if file count exceeds this, use du -sb
	FastScanThreshold int64 = 1000000 // 1M files

	// CacheTTL: how long to trust cached results
	CacheTTL = 5 * time.Minute
)

// ScanPath walks a directory tree and computes detailed usage statistics.
// Automatically uses optimizations:
// - Incremental caching (5 min TTL)
// - Fast scan mode (du -sb) for >1M files
// - Parallel scanning when multiple paths provided via ScanPathsParallel
func ScanPath(path string) (*PathStats, error) {
	return ScanPathWithOptions(path, true, true)
}

// ScanPathWithOptions provides control over scan optimizations
func ScanPathWithOptions(path string, useCache bool, useFastScan bool) (*PathStats, error) {
	stats := &PathStats{}

	// Get filesystem-level statistics (free/total space)
	usedPercent, freeBytes, totalBytes, err := GetDiskUsage(path)
	if err != nil {
		return nil, err
	}
	stats.FreeBytes = freeBytes
	stats.TotalBytes = totalBytes
	_ = usedPercent

	// Check cache first
	if useCache {
		if cached := globalScanCache.get(path); cached != nil {
			if time.Since(cached.timestamp) < CacheTTL {
				// Return cached stats with updated filesystem metrics
				cached.stats.FreeBytes = freeBytes
				cached.stats.TotalBytes = totalBytes
				return cached.stats, nil
			}
		}
	}

	// Perform path-level scan
	var pathUsedBytes int64
	var fileCount int64

	// Check if we should use fast scan mode
	if useFastScan {
		// Quick sample: count first 10K files to estimate total
		sample := estimateFileCount(path, 10000)
		if sample >= FastScanThreshold {
			// Use du -sb for very large trees
			usedBytes, count, err := scanWithDu(path)
			if err == nil {
				pathUsedBytes = usedBytes
				fileCount = count
				goto cacheAndReturn
			}
			// Fall through to WalkDir on error
		}
	}

	// Standard WalkDir scan
	err = filepath.WalkDir(path, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil // Skip errors
		}

		if d.Type().IsRegular() {
			info, err := d.Info()
			if err != nil {
				return nil
			}
			pathUsedBytes += info.Size()
			fileCount++
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

cacheAndReturn:
	stats.UsedBytes = pathUsedBytes
	stats.FileCount = fileCount

	// Update cache
	if useCache {
		globalScanCache.set(path, stats)
	}

	return stats, nil
}

// scanWithDu uses external `du -sb` command for fast scanning of huge trees
func scanWithDu(path string) (usedBytes int64, fileCount int64, err error) {
	// Get used bytes with du -sb
	cmd := exec.Command("du", "-sb", path)
	output, err := cmd.Output()
	if err != nil {
		return 0, 0, fmt.Errorf("du failed: %w", err)
	}

	// Parse: "123456\t/path/to/dir"
	parts := strings.Fields(string(output))
	if len(parts) < 1 {
		return 0, 0, fmt.Errorf("invalid du output")
	}

	usedBytes, err = strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return 0, 0, fmt.Errorf("parse du output: %w", err)
	}

	// Get file count with find (faster than WalkDir for count only)
	cmd = exec.Command("find", path, "-type", "f", "-printf", ".")
	output, err = cmd.Output()
	if err != nil {
		// Non-fatal: return bytes with estimated count
		fileCount = usedBytes / 4096 // Rough estimate: avg 4KB/file
		return usedBytes, fileCount, nil
	}

	fileCount = int64(len(output))
	return usedBytes, fileCount, nil
}

// estimateFileCount does a limited walk to estimate total file count
func estimateFileCount(path string, sampleLimit int) int64 {
	var count int64
	filepath.WalkDir(path, func(p string, d fs.DirEntry, err error) error {
		if err != nil || count >= int64(sampleLimit) {
			return filepath.SkipAll
		}
		if d.Type().IsRegular() {
			count++
		}
		return nil
	})
	return count
}

// ScanPathsParallel scans multiple paths concurrently
func ScanPathsParallel(paths []string) (map[string]*PathStats, error) {
	results := make(map[string]*PathStats)
	var mu sync.Mutex
	var wg sync.WaitGroup
	errChan := make(chan error, len(paths))

	for _, path := range paths {
		wg.Add(1)
		go func(p string) {
			defer wg.Done()

			stats, err := ScanPath(p)
			if err != nil {
				errChan <- fmt.Errorf("scan %s: %w", p, err)
				return
			}

			mu.Lock()
			results[p] = stats
			mu.Unlock()
		}(path)
	}

	wg.Wait()
	close(errChan)

	// Return first error if any
	if err := <-errChan; err != nil {
		return results, err
	}

	return results, nil
}

// Cache methods
func (sc *ScanCache) get(path string) *cachedScan {
	sc.mu.RLock()
	defer sc.mu.RUnlock()
	return sc.cache[path]
}

func (sc *ScanCache) set(path string, stats *PathStats) {
	sc.mu.Lock()
	defer sc.mu.Unlock()
	sc.cache[path] = &cachedScan{
		stats:     stats,
		timestamp: time.Now(),
		fileCount: stats.FileCount,
	}
}

// ClearCache clears all cached scan results
func ClearCache() {
	globalScanCache.mu.Lock()
	defer globalScanCache.mu.Unlock()
	globalScanCache.cache = make(map[string]*cachedScan)
}

// SetFastScanThreshold allows runtime configuration of the threshold
func SetFastScanThreshold(threshold int64) {
	FastScanThreshold = threshold
}

// SetCacheTTL allows runtime configuration of cache TTL
func SetCacheTTL(ttl time.Duration) {
	CacheTTL = ttl
}
