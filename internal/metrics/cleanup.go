package metrics

import (
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// Cleanup subsystem metrics
var (
	// CleanupDuration tracks how long cleanup cycles take
	CleanupDuration prometheus.Histogram

	// BytesFreedTotal tracks total bytes freed across all cleanups
	BytesFreedTotal prometheus.Counter

	// FilesDeletedTotal tracks total files deleted
	FilesDeletedTotal prometheus.Counter

	// CleanupLastRunTimestamp records Unix timestamp of last cleanup
	CleanupLastRunTimestamp prometheus.Gauge

	// CleanupLastMode tracks the last cleanup mode used (AGE, DISK-USAGE, STACK)
	CleanupLastMode *prometheus.GaugeVec

	// PathBytesDeletedTotal tracks bytes deleted per monitored path
	PathBytesDeletedTotal *prometheus.CounterVec

	// Worker pool metrics (beerus-inspired)
	// WorkersActive tracks number of active cleanup workers per path
	WorkersActive *prometheus.GaugeVec

	// BatchesTotal tracks total batches processed per path and status
	BatchesTotal *prometheus.CounterVec

	// BatchDuration tracks duration of batch processing operations
	BatchDuration prometheus.Histogram

	// WorkerErrorsTotal tracks total worker errors per path
	WorkerErrorsTotal *prometheus.CounterVec
)

// initCleanupMetrics initializes all cleanup subsystem metrics
func initCleanupMetrics() {
	CleanupDuration = NewDurationHistogram(
		"storagesage_cleanup_duration_seconds",
		"Duration of cleanup cycles in seconds.",
	)

	BytesFreedTotal = NewBytesCounter(
		"storagesage_bytes_freed_total",
		"Total bytes freed by StorageSage.",
	)

	FilesDeletedTotal = NewCounter(
		"storagesage_files_deleted_total",
		"Total number of files deleted by StorageSage.",
	)

	CleanupLastRunTimestamp = NewSizeGauge(
		"storagesage_cleanup_last_run_timestamp",
		"Timestamp of the last cleanup run (Unix epoch seconds).",
	)

	CleanupLastMode = NewGaugeVec(
		"storagesage_cleanup_last_mode",
		"Last cleanup mode used (1=AGE, 2=DISK-USAGE, 3=STACK).",
		[]string{"mode"},
	)

	PathBytesDeletedTotal = NewCounterVec(
		"storagesage_cleanup_path_bytes_deleted_total",
		"Total bytes deleted per path.",
		[]string{"path"},
	)

	// Initialize worker pool metrics
	WorkersActive = NewGaugeVec(
		"storagesage_cleanup_workers_active",
		"Number of active cleanup workers currently processing files.",
		[]string{"path"},
	)

	BatchesTotal = NewCounterVec(
		"storagesage_cleanup_batches_total",
		"Total number of cleanup batches processed.",
		[]string{"path", "status"},
	)

	BatchDuration = NewDurationHistogram(
		"storagesage_cleanup_batch_duration_seconds",
		"Duration of individual batch processing operations in seconds.",
	)

	WorkerErrorsTotal = NewCounterVec(
		"storagesage_cleanup_worker_errors_total",
		"Total number of errors encountered by cleanup workers.",
		[]string{"path"},
	)
}

// registerCleanupMetrics registers all cleanup metrics with Prometheus
func registerCleanupMetrics() {
	prometheus.MustRegister(CleanupDuration)
	prometheus.MustRegister(BytesFreedTotal)
	prometheus.MustRegister(FilesDeletedTotal)
	prometheus.MustRegister(CleanupLastRunTimestamp)
	prometheus.MustRegister(CleanupLastMode)
	prometheus.MustRegister(PathBytesDeletedTotal)
	prometheus.MustRegister(WorkersActive)
	prometheus.MustRegister(BatchesTotal)
	prometheus.MustRegister(BatchDuration)
	prometheus.MustRegister(WorkerErrorsTotal)
}

// SetCleanupMode sets the current cleanup mode and updates metrics
// Resets all mode gauges to 0, then sets the active mode to 1
func SetCleanupMode(mode string) {
	modeMutex.Lock()
	defer modeMutex.Unlock()

	// Reset all mode gauges to 0
	CleanupLastMode.Reset()

	// Set the current mode to 1
	CleanupLastMode.WithLabelValues(mode).Set(1)
}

// RecordCleanupRun updates the last run timestamp to current time
func RecordCleanupRun() {
	CleanupLastRunTimestamp.Set(float64(time.Now().Unix()))
}

// RecordPathDeletion records bytes deleted for a specific path
func RecordPathDeletion(path string, bytes int64) {
	PathBytesDeletedTotal.WithLabelValues(path).Add(float64(bytes))
}

// Worker pool metric helpers (beerus-inspired)

// SetActiveWorkers sets the number of active workers for a path
func SetActiveWorkers(path string, count int) {
	WorkersActive.WithLabelValues(path).Set(float64(count))
}

// IncrementBatchesTotal increments the total batches counter
func IncrementBatchesTotal(path string, status string) {
	BatchesTotal.WithLabelValues(path, status).Inc()
}

// RecordBatchDuration records the duration of a batch operation
func RecordBatchDuration(path string, durationSeconds float64) {
	BatchDuration.Observe(durationSeconds)
}

// IncrementWorkerErrors increments the worker error counter
func IncrementWorkerErrors(path string, count int64) {
	WorkerErrorsTotal.WithLabelValues(path).Add(float64(count))
}
