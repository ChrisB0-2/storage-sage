package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
)

// Standard histogram buckets for different metric types
var (
	// DurationBuckets: 100ms to 5min for cleanup/operation durations
	DurationBuckets = []float64{0.1, 0.5, 1, 5, 10, 30, 60, 300}

	// BytesBuckets: 1KB to 1GB for storage size tracking
	BytesBuckets = []float64{1024, 10240, 102400, 1048576, 10485760, 104857600, 1073741824}

	// APIBuckets: 100ms to 10s for HTTP request durations
	APIBuckets = []float64{0.1, 0.5, 1, 5, 10}
)

// NewDurationHistogram creates a histogram for tracking durations in seconds
// with standard buckets: [0.1, 0.5, 1, 5, 10, 30, 60, 300]
func NewDurationHistogram(name, help string) prometheus.Histogram {
	return prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    name,
		Help:    help,
		Buckets: DurationBuckets,
	})
}

// NewBytesCounter creates a counter for tracking bytes
func NewBytesCounter(name, help string) prometheus.Counter {
	return prometheus.NewCounter(prometheus.CounterOpts{
		Name: name,
		Help: help,
	})
}

// NewCounter creates a standard counter metric
func NewCounter(name, help string) prometheus.Counter {
	return prometheus.NewCounter(prometheus.CounterOpts{
		Name: name,
		Help: help,
	})
}

// NewSizeGauge creates a gauge for tracking storage sizes
func NewSizeGauge(name, help string) prometheus.Gauge {
	return prometheus.NewGauge(prometheus.GaugeOpts{
		Name: name,
		Help: help,
	})
}

// NewSizeGaugeVec creates a labeled gauge for tracking storage sizes
func NewSizeGaugeVec(name, help string, labels []string) *prometheus.GaugeVec {
	return prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: name,
		Help: help,
	}, labels)
}

// NewCounterVec creates a labeled counter
func NewCounterVec(name, help string, labels []string) *prometheus.CounterVec {
	return prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: name,
		Help: help,
	}, labels)
}

// NewGaugeVec creates a labeled gauge
func NewGaugeVec(name, help string, labels []string) *prometheus.GaugeVec {
	return prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: name,
		Help: help,
	}, labels)
}

// NewGauge creates a standard gauge metric
func NewGauge(name, help string) prometheus.Gauge {
	return prometheus.NewGauge(prometheus.GaugeOpts{
		Name: name,
		Help: help,
	})
}
