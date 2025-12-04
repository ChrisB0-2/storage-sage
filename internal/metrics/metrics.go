package metrics

import (
	"context"
	"log"
	"net/http"
	"os"
	"sync"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// Core synchronization primitives
	initOnce       sync.Once
	serverMutex    sync.Mutex
	modeMutex      sync.RWMutex
	currentSrv     *http.Server
	triggerChannel chan os.Signal
	reloadChannel  chan os.Signal
	currentMode    string

	// Global health checker instance
	globalHealthChecker *HealthChecker
	healthMutex         sync.RWMutex
)

// Init initializes all metrics subsystems and registers them with Prometheus
// This function is safe to call multiple times (uses sync.Once)
func Init() {
	initOnce.Do(func() {
		// Initialize all subsystem metrics
		initCleanupMetrics()
		initDaemonMetrics()
		initAPIMetrics()
		initServiceHealthMetrics()

		// Register all metrics with Prometheus
		registerCleanupMetrics()
		registerDaemonMetrics()
		registerAPIMetrics()
		registerServiceHealthMetrics()

		// Initialize metrics with default values so they appear in /metrics immediately
		// Even before first cleanup run (required for test compliance)
		CleanupLastRunTimestamp.Set(0)
		CleanupLastMode.WithLabelValues("NONE").Set(0)

		// Initialize trigger channel for cleanup signals
		triggerChannel = make(chan os.Signal, 1)
	})
}

// SetTriggerChannel sets the channel for triggering cleanup cycles
func SetTriggerChannel(ch chan os.Signal) {
	triggerChannel = ch
}

// SetReloadChannel sets the channel for triggering config reloads
func SetReloadChannel(ch chan os.Signal) {
	reloadChannel = ch
}

// StartServer starts the metrics HTTP server on the specified address
// Exposes /metrics (Prometheus), /health, and /trigger endpoints
func StartServer(addr string, logger *log.Logger) {
	serverMutex.Lock()
	defer serverMutex.Unlock()

	if currentSrv != nil {
		logger.Printf("metrics server already running on %s", currentSrv.Addr)
		return
	}

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())

	// Add health endpoint (Spec Section 7.1)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		healthMutex.RLock()
		hc := globalHealthChecker
		healthMutex.RUnlock()

		if hc != nil && hc.IsHealthy() {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(`{"status":"ok","healthy":true}`))
		} else if hc != nil {
			// Report unhealthy state with component details
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte(`{"status":"degraded","healthy":false}`))
		} else {
			// No health checker configured, default to ok
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(`{"status":"ok","healthy":true}`))
		}
	})

	// Add trigger endpoint
	mux.HandleFunc("/trigger", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Send USR1 signal to trigger cleanup
		if triggerChannel != nil {
			select {
			case triggerChannel <- syscall.SIGUSR1:
				w.WriteHeader(http.StatusOK)
				w.Write([]byte("Cleanup triggered"))
			default:
				http.Error(w, "Trigger channel full", http.StatusServiceUnavailable)
			}
		} else {
			http.Error(w, "Trigger channel not initialized", http.StatusServiceUnavailable)
		}
	})

	// Add reload endpoint for config reload
	mux.HandleFunc("/reload", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Send HUP signal to trigger config reload
		if reloadChannel != nil {
			select {
			case reloadChannel <- syscall.SIGHUP:
				w.WriteHeader(http.StatusOK)
				w.Write([]byte("Config reload triggered"))
			default:
				http.Error(w, "Reload channel full", http.StatusServiceUnavailable)
			}
		} else {
			http.Error(w, "Reload channel not initialized", http.StatusServiceUnavailable)
		}
	})

	srv := &http.Server{
		Addr:    addr,
		Handler: mux,
	}
	currentSrv = srv

	go func() {
		logger.Printf("metrics server listening on %s", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Printf("metrics server error: %v", err)
			ErrorsTotal.Inc()
		}
	}()

	// Give server 100ms to start
	time.Sleep(100 * time.Millisecond)
}

// Shutdown gracefully shuts down the metrics server
func Shutdown(ctx context.Context, logger *log.Logger) {
	serverMutex.Lock()
	defer serverMutex.Unlock()

	// Stop health checker if running
	healthMutex.Lock()
	if globalHealthChecker != nil {
		globalHealthChecker.Stop()
		globalHealthChecker = nil
	}
	healthMutex.Unlock()

	if currentSrv == nil {
		return
	}

	if err := currentSrv.Shutdown(ctx); err != nil {
		logger.Printf("metrics server shutdown error: %v", err)
		ErrorsTotal.Inc()
	}
	currentSrv = nil
}

// SetHealthChecker sets the global health checker instance
func SetHealthChecker(hc *HealthChecker) {
	healthMutex.Lock()
	defer healthMutex.Unlock()
	globalHealthChecker = hc
}

// GetHealthChecker returns the global health checker instance
func GetHealthChecker() *HealthChecker {
	healthMutex.RLock()
	defer healthMutex.RUnlock()
	return globalHealthChecker
}
