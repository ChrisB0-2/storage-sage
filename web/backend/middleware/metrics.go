package middleware

import (
	"net/http"
	"strconv"
	"time"

	"storage-sage/internal/metrics"
)

// responseWriter wraps http.ResponseWriter to capture status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
	written    bool
}

func (rw *responseWriter) WriteHeader(code int) {
	if !rw.written {
		rw.statusCode = code
		rw.written = true
		rw.ResponseWriter.WriteHeader(code)
	}
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	if !rw.written {
		rw.statusCode = http.StatusOK
		rw.written = true
	}
	return rw.ResponseWriter.Write(b)
}

// MetricsMiddleware instruments HTTP handlers with Prometheus metrics
// Tracks request duration and count per handler, method, and status code
func MetricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap response writer to capture status code
		wrapped := &responseWriter{
			ResponseWriter: w,
			statusCode:     http.StatusOK,
			written:        false,
		}

		// Call next handler
		next.ServeHTTP(wrapped, r)

		// SAFETY: Only record metrics if they're initialized
		// This prevents crashes when metrics.Init() hasn't been called in the backend
		// The backend doesn't initialize metrics by default to avoid import cycles
		if metrics.HTTPRequestDuration == nil || metrics.HTTPRequestsTotal == nil {
			return // Skip metrics recording gracefully
		}

		// Record metrics
		duration := time.Since(start).Seconds()
		status := strconv.Itoa(wrapped.statusCode)

		// Extract handler name from URL path
		handlerName := r.URL.Path
		if handlerName == "" {
			handlerName = "unknown"
		}

		// Record duration histogram
		metrics.HTTPRequestDuration.WithLabelValues(
			handlerName,
			r.Method,
			status,
		).Observe(duration)

		// Increment request counter
		metrics.HTTPRequestsTotal.WithLabelValues(
			handlerName,
			r.Method,
			status,
		).Inc()
	})
}
