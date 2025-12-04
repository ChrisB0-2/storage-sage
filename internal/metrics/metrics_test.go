package metrics

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus"
)

// TestMetricsInit verifies that Init() is idempotent and registers metrics
func TestMetricsInit(t *testing.T) {
	// Create a new registry for isolated testing
	reg := prometheus.NewRegistry()

	// Save original default registerer
	// Note: In production, metrics use prometheus.DefaultRegisterer
	// For this test, we'll verify metrics are created without panicking

	// Call Init multiple times - should be idempotent via sync.Once
	Init()
	Init()
	Init()

	// Verify metrics are non-nil (successfully created)
	if CleanupDuration == nil {
		t.Error("CleanupDuration should be initialized")
	}
	if BytesFreedTotal == nil {
		t.Error("BytesFreedTotal should be initialized")
	}
	if FilesDeletedTotal == nil {
		t.Error("FilesDeletedTotal should be initialized")
	}
	if CleanupLastRunTimestamp == nil {
		t.Error("CleanupLastRunTimestamp should be initialized")
	}
	if CleanupLastMode == nil {
		t.Error("CleanupLastMode should be initialized")
	}
	if PathBytesDeletedTotal == nil {
		t.Error("PathBytesDeletedTotal should be initialized")
	}
	if ErrorsTotal == nil {
		t.Error("ErrorsTotal should be initialized")
	}
	if FreeSpacePercent == nil {
		t.Error("FreeSpacePercent should be initialized")
	}
	if HTTPRequestDuration == nil {
		t.Error("HTTPRequestDuration should be initialized")
	}
	if HTTPRequestsTotal == nil {
		t.Error("HTTPRequestsTotal should be initialized")
	}

	// Test metrics are registered by gathering from default registry
	mfs, err := prometheus.DefaultGatherer.Gather()
	if err != nil {
		t.Fatalf("Failed to gather metrics: %v", err)
	}

	// Check for expected metric names
	expectedMetrics := []string{
		"storagesage_cleanup_duration_seconds",
		"storagesage_bytes_freed_total",
		"storagesage_files_deleted_total",
		"storagesage_cleanup_last_run_timestamp",
		"storagesage_cleanup_last_mode",
		"storagesage_cleanup_path_bytes_deleted_total",
		"storagesage_daemon_errors_total",
		"storagesage_daemon_free_space_percent",
		"storagesage_api_request_duration_seconds",
		"storagesage_api_requests_total",
	}

	foundMetrics := make(map[string]bool)
	for _, mf := range mfs {
		foundMetrics[*mf.Name] = true
	}

	for _, expected := range expectedMetrics {
		if !foundMetrics[expected] {
			t.Errorf("Expected metric %s not found in registry", expected)
		}
	}

	// Use the isolated registry for a clean test
	_ = reg
}

// TestHelperFunctions verifies that helper functions create valid metrics
func TestHelperFunctions(t *testing.T) {
	t.Run("NewDurationHistogram", func(t *testing.T) {
		h := NewDurationHistogram("test_duration", "Test duration metric")
		if h == nil {
			t.Error("NewDurationHistogram returned nil")
		}
	})

	t.Run("NewBytesCounter", func(t *testing.T) {
		c := NewBytesCounter("test_bytes", "Test bytes metric")
		if c == nil {
			t.Error("NewBytesCounter returned nil")
		}
	})

	t.Run("NewCounter", func(t *testing.T) {
		c := NewCounter("test_counter", "Test counter metric")
		if c == nil {
			t.Error("NewCounter returned nil")
		}
	})

	t.Run("NewSizeGauge", func(t *testing.T) {
		g := NewSizeGauge("test_gauge", "Test gauge metric")
		if g == nil {
			t.Error("NewSizeGauge returned nil")
		}
	})

	t.Run("NewSizeGaugeVec", func(t *testing.T) {
		gv := NewSizeGaugeVec("test_gauge_vec", "Test gauge vec metric", []string{"label"})
		if gv == nil {
			t.Error("NewSizeGaugeVec returned nil")
		}
	})

	t.Run("NewCounterVec", func(t *testing.T) {
		cv := NewCounterVec("test_counter_vec", "Test counter vec metric", []string{"label"})
		if cv == nil {
			t.Error("NewCounterVec returned nil")
		}
	})

	t.Run("NewGaugeVec", func(t *testing.T) {
		gv := NewGaugeVec("test_gauge_vec2", "Test gauge vec metric", []string{"label"})
		if gv == nil {
			t.Error("NewGaugeVec returned nil")
		}
	})
}

// TestStandardBuckets verifies that standard bucket definitions are correct
func TestStandardBuckets(t *testing.T) {
	t.Run("DurationBuckets", func(t *testing.T) {
		expected := []float64{0.1, 0.5, 1, 5, 10, 30, 60, 300}
		if len(DurationBuckets) != len(expected) {
			t.Errorf("Expected %d duration buckets, got %d", len(expected), len(DurationBuckets))
		}
		for i, v := range expected {
			if DurationBuckets[i] != v {
				t.Errorf("Duration bucket[%d]: expected %v, got %v", i, v, DurationBuckets[i])
			}
		}
	})

	t.Run("BytesBuckets", func(t *testing.T) {
		expected := []float64{1024, 10240, 102400, 1048576, 10485760, 104857600, 1073741824}
		if len(BytesBuckets) != len(expected) {
			t.Errorf("Expected %d bytes buckets, got %d", len(expected), len(BytesBuckets))
		}
		for i, v := range expected {
			if BytesBuckets[i] != v {
				t.Errorf("Bytes bucket[%d]: expected %v, got %v", i, v, BytesBuckets[i])
			}
		}
	})

	t.Run("APIBuckets", func(t *testing.T) {
		expected := []float64{0.1, 0.5, 1, 5, 10}
		if len(APIBuckets) != len(expected) {
			t.Errorf("Expected %d API buckets, got %d", len(expected), len(APIBuckets))
		}
		for i, v := range expected {
			if APIBuckets[i] != v {
				t.Errorf("API bucket[%d]: expected %v, got %v", i, v, APIBuckets[i])
			}
		}
	})
}

// TestCleanupMetricHelpers tests cleanup subsystem helper functions
func TestCleanupMetricHelpers(t *testing.T) {
	Init() // Ensure metrics are initialized

	t.Run("SetCleanupMode", func(t *testing.T) {
		// Should not panic
		SetCleanupMode("AGE")
		SetCleanupMode("DISK-USAGE")
		SetCleanupMode("STACK")
	})

	t.Run("RecordCleanupRun", func(t *testing.T) {
		// Should not panic
		RecordCleanupRun()
	})

	t.Run("RecordPathDeletion", func(t *testing.T) {
		// Should not panic
		RecordPathDeletion("/test/path", 1024)
		RecordPathDeletion("/another/path", 2048)
	})
}

// TestDaemonMetricHelpers tests daemon subsystem helper functions
func TestDaemonMetricHelpers(t *testing.T) {
	Init() // Ensure metrics are initialized

	t.Run("UpdateFreeSpacePercent", func(t *testing.T) {
		// Should not panic
		UpdateFreeSpacePercent("/test/path", 85.5)
		UpdateFreeSpacePercent("/another/path", 42.3)
	})
}

// TestMetricIncrements verifies metrics can be incremented/updated
func TestMetricIncrements(t *testing.T) {
	Init()

	t.Run("IncrementCounters", func(t *testing.T) {
		// Should not panic
		FilesDeletedTotal.Inc()
		BytesFreedTotal.Add(1024)
		ErrorsTotal.Inc()
	})

	t.Run("ObserveHistogram", func(t *testing.T) {
		// Should not panic
		CleanupDuration.Observe(1.5)
		CleanupDuration.Observe(30.2)
	})

	t.Run("SetGauges", func(t *testing.T) {
		// Should not panic
		CleanupLastRunTimestamp.Set(1234567890)
	})

	t.Run("LabeledMetrics", func(t *testing.T) {
		// Should not panic
		HTTPRequestDuration.WithLabelValues("/api/health", "GET", "200").Observe(0.05)
		HTTPRequestsTotal.WithLabelValues("/api/health", "GET", "200").Inc()
	})
}
