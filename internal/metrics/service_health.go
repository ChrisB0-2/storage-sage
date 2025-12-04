package metrics

import (
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// Service health metrics following systemd_exporter patterns
var (
	// ServiceHealthy indicates overall daemon health status
	ServiceHealthy *prometheus.GaugeVec

	// SystemdUnitState tracks systemd unit state (active/inactive/failed)
	SystemdUnitState *prometheus.GaugeVec

	// ServiceRestarts counts daemon restart events
	ServiceRestarts *prometheus.CounterVec

	// ServiceStartTime records daemon start timestamp
	ServiceStartTime prometheus.Gauge

	// ComponentHealthy tracks individual component health
	ComponentHealthy *prometheus.GaugeVec

	// LastHealthCheck records timestamp of last successful health check
	LastHealthCheck *prometheus.GaugeVec

	// HealthCheckDuration tracks health check execution time
	HealthCheckDuration *prometheus.HistogramVec

	// HealthCheckFailures counts consecutive failures per component
	HealthCheckFailures *prometheus.GaugeVec
)

// HealthChecker manages periodic health checks for service components
type HealthChecker struct {
	mu               sync.RWMutex
	startTime        time.Time
	components       map[string]*ComponentHealth
	checkInterval    time.Duration
	stopCh           chan struct{}
	wg               sync.WaitGroup
	started          bool
}

// ComponentHealth represents health status of a single component
type ComponentHealth struct {
	Name         string
	LastCheck    time.Time
	Healthy      bool
	CheckFunc    func() error
	FailureCount int
	Timeout      time.Duration
}

// initServiceHealthMetrics initializes all service health metrics
func initServiceHealthMetrics() {
	ServiceHealthy = NewGaugeVec(
		"storagesage_daemon_healthy",
		"Daemon health status (1=healthy, 0=unhealthy).",
		[]string{"component"},
	)

	SystemdUnitState = NewGaugeVec(
		"storagesage_systemd_unit_state",
		"Systemd unit state (1=active, 0=inactive, -1=failed).",
		[]string{"unit", "state"},
	)

	ServiceRestarts = NewCounterVec(
		"storagesage_daemon_restarts_total",
		"Total number of daemon restarts detected.",
		[]string{"reason"},
	)

	ServiceStartTime = NewGauge(
		"storagesage_daemon_start_timestamp_seconds",
		"Unix timestamp when daemon started.",
	)

	ComponentHealthy = NewGaugeVec(
		"storagesage_component_healthy",
		"Individual component health status (1=healthy, 0=unhealthy).",
		[]string{"component", "check_type"},
	)

	LastHealthCheck = NewGaugeVec(
		"storagesage_last_health_check_timestamp_seconds",
		"Unix timestamp of last health check.",
		[]string{"component"},
	)

	HealthCheckDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "storagesage_health_check_duration_seconds",
			Help:    "Time taken to execute health checks.",
			Buckets: []float64{.001, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5},
		},
		[]string{"component"},
	)

	HealthCheckFailures = NewGaugeVec(
		"storagesage_health_check_failures_consecutive",
		"Consecutive health check failures per component.",
		[]string{"component"},
	)

	HealthCheckTimeouts = NewCounter(
		"storagesage_health_check_timeouts_total",
		"Total number of health check timeouts.",
	)
}

// registerServiceHealthMetrics registers all service health metrics
func registerServiceHealthMetrics() {
	prometheus.MustRegister(ServiceHealthy)
	prometheus.MustRegister(SystemdUnitState)
	prometheus.MustRegister(ServiceRestarts)
	prometheus.MustRegister(ServiceStartTime)
	prometheus.MustRegister(ComponentHealthy)
	prometheus.MustRegister(LastHealthCheck)
	prometheus.MustRegister(HealthCheckDuration)
	prometheus.MustRegister(HealthCheckFailures)
	prometheus.MustRegister(HealthCheckTimeouts)
}

// NewHealthChecker creates a new health checker with specified check interval
func NewHealthChecker(interval time.Duration) *HealthChecker {
	hc := &HealthChecker{
		startTime:     time.Now(),
		components:    make(map[string]*ComponentHealth),
		checkInterval: interval,
		stopCh:        make(chan struct{}),
		started:       false,
	}

	// Record daemon start time
	ServiceStartTime.Set(float64(hc.startTime.Unix()))

	// Initialize overall health to healthy
	ServiceHealthy.WithLabelValues("overall").Set(1)

	return hc
}

// RegisterComponent adds a component health check
// name: component identifier
// checkFunc: function returning nil on success, error on failure
// timeout: max duration for health check (0 = no timeout)
func (hc *HealthChecker) RegisterComponent(name string, checkFunc func() error, timeout time.Duration) {
	hc.mu.Lock()
	defer hc.mu.Unlock()

	hc.components[name] = &ComponentHealth{
		Name:      name,
		CheckFunc: checkFunc,
		Healthy:   true,
		Timeout:   timeout,
	}

	// Initialize metrics for this component
	ComponentHealthy.WithLabelValues(name, "functional").Set(1)
	HealthCheckFailures.WithLabelValues(name).Set(0)
}

// Start begins periodic health checking
// Must be called after registering all components
func (hc *HealthChecker) Start() {
	hc.mu.Lock()
	if hc.started {
		hc.mu.Unlock()
		return
	}
	hc.started = true
	hc.mu.Unlock()

	hc.wg.Add(1)
	go hc.runHealthCheckLoop()
}

// Stop halts health checking and waits for completion
func (hc *HealthChecker) Stop() {
	hc.mu.Lock()
	if !hc.started {
		hc.mu.Unlock()
		return
	}
	hc.mu.Unlock()

	close(hc.stopCh)
	hc.wg.Wait()
}

// runHealthCheckLoop executes health checks on interval
func (hc *HealthChecker) runHealthCheckLoop() {
	defer hc.wg.Done()

	ticker := time.NewTicker(hc.checkInterval)
	defer ticker.Stop()

	// Run initial health check immediately
	hc.runHealthChecks()

	for {
		select {
		case <-ticker.C:
			hc.runHealthChecks()
		case <-hc.stopCh:
			return
		}
	}
}

// runHealthChecks executes all registered health checks
func (hc *HealthChecker) runHealthChecks() {
	hc.mu.Lock()
	defer hc.mu.Unlock()

	overallHealthy := true

	for name, comp := range hc.components {
		start := time.Now()

		// Execute health check with optional timeout
		var err error
		if comp.Timeout > 0 {
			err = hc.runWithTimeout(comp.CheckFunc, comp.Timeout)
		} else {
			err = comp.CheckFunc()
		}

		duration := time.Since(start).Seconds()
		HealthCheckDuration.WithLabelValues(name).Observe(duration)

		comp.LastCheck = time.Now()
		LastHealthCheck.WithLabelValues(name).Set(float64(comp.LastCheck.Unix()))

		if err != nil {
			comp.Healthy = false
			comp.FailureCount++
			overallHealthy = false

			ComponentHealthy.WithLabelValues(name, "functional").Set(0)
			HealthCheckFailures.WithLabelValues(name).Set(float64(comp.FailureCount))

			// Increment error counter for monitoring
			ErrorsTotal.Inc()
		} else {
			comp.Healthy = true
			comp.FailureCount = 0

			ComponentHealthy.WithLabelValues(name, "functional").Set(1)
			HealthCheckFailures.WithLabelValues(name).Set(0)
		}
	}

	// Update overall health status
	if overallHealthy {
		ServiceHealthy.WithLabelValues("overall").Set(1)
	} else {
		ServiceHealthy.WithLabelValues("overall").Set(0)
	}
}

// runWithTimeout executes a function with timeout
func (hc *HealthChecker) runWithTimeout(fn func() error, timeout time.Duration) error {
	errCh := make(chan error, 1)

	go func() {
		errCh <- fn()
	}()

	select {
	case err := <-errCh:
		return err
	case <-time.After(timeout):
		HealthCheckTimeouts.Inc()
		return errHealthCheckTimeout
	}
}

// Error types
var errHealthCheckTimeout = &healthCheckTimeoutError{}

type healthCheckTimeoutError struct{}

func (e *healthCheckTimeoutError) Error() string {
	return "health check timeout"
}

// HealthCheckTimeouts counter tracks timeout events
var HealthCheckTimeouts prometheus.Counter

// GetHealth returns current health status of all components
func (hc *HealthChecker) GetHealth() map[string]bool {
	hc.mu.RLock()
	defer hc.mu.RUnlock()

	health := make(map[string]bool)
	for name, comp := range hc.components {
		health[name] = comp.Healthy
	}
	return health
}

// IsHealthy returns true if all components are healthy
func (hc *HealthChecker) IsHealthy() bool {
	hc.mu.RLock()
	defer hc.mu.RUnlock()

	for _, comp := range hc.components {
		if !comp.Healthy {
			return false
		}
	}
	return true
}

// GetUptime returns daemon uptime in seconds
func (hc *HealthChecker) GetUptime() float64 {
	return time.Since(hc.startTime).Seconds()
}

// RecordRestart increments restart counter with reason
func RecordRestart(reason string) {
	ServiceRestarts.WithLabelValues(reason).Inc()
}

// UpdateSystemdUnitState updates systemd unit state metric
// state: "active", "inactive", "failed"
func UpdateSystemdUnitState(unit string, state string) {
	// Reset all state labels
	SystemdUnitState.WithLabelValues(unit, "active").Set(0)
	SystemdUnitState.WithLabelValues(unit, "inactive").Set(0)
	SystemdUnitState.WithLabelValues(unit, "failed").Set(0)

	// Set current state
	value := 0.0
	switch state {
	case "active":
		value = 1.0
	case "inactive":
		value = 0.0
	case "failed":
		value = -1.0
	}
	SystemdUnitState.WithLabelValues(unit, state).Set(value)
}
