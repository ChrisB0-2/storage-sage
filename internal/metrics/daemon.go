package metrics

import (
	"github.com/prometheus/client_golang/prometheus"

	"storage-sage/internal/disk"
)

// Daemon subsystem metrics
var (
	// ErrorsTotal tracks total errors encountered by the daemon
	ErrorsTotal prometheus.Counter

	// FreeSpacePercent tracks current free space percentage per monitored path
	FreeSpacePercent *prometheus.GaugeVec

	// PathUsedBytes tracks total bytes used within a monitored path (path-level scan)
	PathUsedBytes *prometheus.GaugeVec

	// PathFilesTotal tracks total number of files within a monitored path
	PathFilesTotal *prometheus.GaugeVec

	// PathFreeBytes tracks free space available on the filesystem containing the path
	PathFreeBytes *prometheus.GaugeVec

	// PathTotalBytes tracks total capacity of the filesystem containing the path
	PathTotalBytes *prometheus.GaugeVec
)

// initDaemonMetrics initializes all daemon subsystem metrics
func initDaemonMetrics() {
	ErrorsTotal = NewCounter(
		"storagesage_daemon_errors_total",
		"Total number of errors encountered by StorageSage.",
	)

	FreeSpacePercent = NewSizeGaugeVec(
		"storagesage_daemon_free_space_percent",
		"Current free space percentage for monitored paths.",
		[]string{"path"},
	)

	PathUsedBytes = NewSizeGaugeVec(
		"storagesage_path_used_bytes",
		"Total bytes used within the monitored path (directory tree scan).",
		[]string{"path"},
	)

	PathFilesTotal = NewSizeGaugeVec(
		"storagesage_path_files_total",
		"Total number of regular files within the monitored path.",
		[]string{"path"},
	)

	PathFreeBytes = NewSizeGaugeVec(
		"storagesage_path_free_bytes",
		"Free space available on the filesystem containing this path.",
		[]string{"path"},
	)

	PathTotalBytes = NewSizeGaugeVec(
		"storagesage_path_total_bytes",
		"Total capacity of the filesystem containing this path.",
		[]string{"path"},
	)
}

// registerDaemonMetrics registers all daemon metrics with Prometheus
func registerDaemonMetrics() {
	prometheus.MustRegister(ErrorsTotal)
	prometheus.MustRegister(FreeSpacePercent)
	prometheus.MustRegister(PathUsedBytes)
	prometheus.MustRegister(PathFilesTotal)
	prometheus.MustRegister(PathFreeBytes)
	prometheus.MustRegister(PathTotalBytes)
}

// UpdateFreeSpacePercent updates the free space percentage for a path
func UpdateFreeSpacePercent(path string, percent float64) {
	FreeSpacePercent.WithLabelValues(path).Set(percent)
}

// UpdateAllDiskMetrics updates all disk-related metrics for a path.
// This includes both filesystem-level metrics (free/total space) and
// path-level metrics (used bytes and file count from scanning the directory).
//
// Pass stats from disk.ScanPath() to populate all metrics atomically.
func UpdateAllDiskMetrics(path string, stats *disk.PathStats) {
	// Filesystem-level metrics
	freePercent := 100.0
	if stats.TotalBytes > 0 {
		freePercent = (float64(stats.FreeBytes) / float64(stats.TotalBytes)) * 100.0
	}
	FreeSpacePercent.WithLabelValues(path).Set(freePercent)
	PathFreeBytes.WithLabelValues(path).Set(float64(stats.FreeBytes))
	PathTotalBytes.WithLabelValues(path).Set(float64(stats.TotalBytes))

	// Path-level metrics (scanned usage)
	PathUsedBytes.WithLabelValues(path).Set(float64(stats.UsedBytes))
	PathFilesTotal.WithLabelValues(path).Set(float64(stats.FileCount))
}
