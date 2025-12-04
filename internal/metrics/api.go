package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
)

// API/HTTP subsystem metrics
var (
	// HTTPRequestDuration tracks HTTP request latency
	HTTPRequestDuration *prometheus.HistogramVec

	// HTTPRequestsTotal tracks total HTTP requests by handler, method, status
	HTTPRequestsTotal *prometheus.CounterVec
)

// initAPIMetrics initializes all API subsystem metrics
func initAPIMetrics() {
	HTTPRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "storagesage_api_request_duration_seconds",
			Help:    "HTTP request duration in seconds.",
			Buckets: APIBuckets,
		},
		[]string{"handler", "method", "status"},
	)

	HTTPRequestsTotal = NewCounterVec(
		"storagesage_api_requests_total",
		"Total HTTP requests processed by StorageSage API.",
		[]string{"handler", "method", "status"},
	)
}

// registerAPIMetrics registers all API metrics with Prometheus
func registerAPIMetrics() {
	prometheus.MustRegister(HTTPRequestDuration)
	prometheus.MustRegister(HTTPRequestsTotal)
}
