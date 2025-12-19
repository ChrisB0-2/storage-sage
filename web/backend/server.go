package main

import (
	"context"
	"crypto/tls"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"storage-sage/web/backend/api"
	"storage-sage/web/backend/auth"
	"storage-sage/web/backend/middleware"
	"storage-sage/web/backend/websocket"

	"github.com/gorilla/mux"
	"golang.org/x/time/rate"
)

const (
	ServerAddr      = ":8443"
	ReadTimeout     = 15 * time.Second
	WriteTimeout    = 15 * time.Second
	IdleTimeout     = 60 * time.Second
	ShutdownTimeout = 10 * time.Second
)

func main() {
	logger := log.New(os.Stdout, "[storage-sage-web] ", log.LstdFlags|log.Lshortfile)

	// Get JWT secret from file (Docker secrets) or environment variable (fallback)
	var jwtSecret string
	secretFile := os.Getenv("JWT_SECRET_FILE")
	if secretFile != "" {
		// Read from Docker secret file
		secretBytes, err := os.ReadFile(secretFile)
		if err != nil {
			logger.Printf("ERROR: Failed to read JWT secret file %s: %v", secretFile, err)
			logger.Fatalf("Cannot start without valid JWT secret")
		}
		jwtSecret = strings.TrimSpace(string(secretBytes))
		logger.Println("Loaded JWT secret from file (Docker secrets)")
	} else {
		// Fallback to environment variable (for backwards compatibility)
		jwtSecret = os.Getenv("JWT_SECRET")
		if jwtSecret == "" {
			jwtSecret = "your-secret-key-change-this" // Fallback for dev only
			logger.Println("WARNING: Using default JWT secret. Set JWT_SECRET_FILE or JWT_SECRET env var in production!")
		} else {
			logger.Println("WARNING: Using JWT_SECRET env var. Consider using JWT_SECRET_FILE with Docker secrets for better security.")
		}
	}

	// Get JWT expiry from environment
	jwtExpiryStr := os.Getenv("JWT_EXPIRY")
	if jwtExpiryStr == "" {
		jwtExpiryStr = "24h"
	}
	jwtExpiry, err := time.ParseDuration(jwtExpiryStr)
	if err != nil {
		jwtExpiry = 24 * time.Hour
		logger.Printf("Invalid JWT_EXPIRY, using default: %v", err)
	}

	// Initialize JWT manager
	jwtManager := auth.NewJWTManager(jwtSecret, jwtExpiry)

	// Initialize metrics (required for middleware)
	// Note: Import added at top - "storage-sage/internal/metrics"
	// This is safe to call even though daemon also calls it (idempotent)
	// Backend needs metrics for HTTP instrumentation middleware
	// Daemon metrics are separate and exposed on different port
	// metrics.Init() // COMMENTED OUT - causes import cycle, middleware will be disabled

	// Initialize WebSocket hub
	hub := websocket.NewHub()
	go hub.Run()

	// Create router
	router := mux.NewRouter()

	// Apply global middleware
	router.Use(middleware.LoggingMiddleware(logger))
	// router.Use(middleware.MetricsMiddleware) // Prometheus instrumentation - DISABLED (metrics not initialized)
	router.Use(middleware.CORSMiddleware)
	router.Use(middleware.SecurityHeadersMiddleware)
	// Limit request body size to 1MB to prevent DoS attacks
	router.Use(middleware.RequestBodySizeLimitMiddleware(1 << 20)) // 1MB
	// Global rate limiting: 100 requests per second with burst of 200
	router.Use(middleware.RateLimitMiddleware(rate.Limit(100), 200))

	// Public routes (no auth required)
	// Stricter rate limiting for login endpoint: 5 requests per second with burst of 10
	loginRouter := router.PathPrefix("/api/v1/auth").Subrouter()
	loginRouter.Use(middleware.RateLimitMiddleware(rate.Limit(5), 10))
	loginRouter.HandleFunc("/login", api.LoginHandler(jwtManager)).Methods("POST")

	router.HandleFunc("/api/v1/health", api.HealthHandler).Methods("GET", "HEAD")

	// Protected routes (require JWT)
	protected := router.PathPrefix("/api/v1").Subrouter()
	protected.Use(middleware.AuthMiddleware(jwtManager))

	// Config management endpoints
	protected.HandleFunc("/config", api.GetConfigHandler).Methods("GET")
	protected.HandleFunc("/config", api.UpdateConfigHandler).Methods("PUT")
	protected.HandleFunc("/config/validate", api.ValidateConfigHandler).Methods("POST")

	// Metrics endpoints
	protected.HandleFunc("/metrics/current", api.GetMetricsHandler).Methods("GET")
	protected.HandleFunc("/metrics/history", api.GetMetricsHistoryHandler).Methods("GET")

	// Cleanup control
	protected.HandleFunc("/cleanup/trigger", api.TriggerCleanupHandler).Methods("POST")
	protected.HandleFunc("/cleanup/status", api.GetCleanupStatusHandler).Methods("GET")

	// Logs endpoints
	protected.HandleFunc("/deletions/log", api.GetDeletionsLogHandler).Methods("GET")

	// WebSocket endpoint for live metrics
	protected.HandleFunc("/ws/metrics", websocket.HandleMetricsWebSocket(hub)).Methods("GET")

	// Serve frontend static files (React/Vite build output)
	// Priority order: /app/frontend/dist (container), frontend/dist (local), ../frontend/dist (local)
	frontendPath := "/app/frontend/dist"
	if _, err := os.Stat(frontendPath); os.IsNotExist(err) {
		frontendPath = "frontend/dist"
		if _, err := os.Stat(frontendPath); os.IsNotExist(err) {
			frontendPath = "../frontend/dist"
			if _, err := os.Stat(frontendPath); os.IsNotExist(err) {
				logger.Printf("WARNING: Frontend dist not found in any expected location. UI will not work!")
				logger.Printf("  Tried: /app/frontend/dist, frontend/dist, ../frontend/dist")
				logger.Printf("  Please build frontend with: cd web/frontend && npm install && npm run build")
			}
		}
	}

	logger.Printf("Serving frontend from: %s", frontendPath)

	// Explicitly handle /index.html to prevent 301 redirects from catch-all handler
	// Must be registered BEFORE PathPrefix("/") to take precedence
	router.HandleFunc("/index.html", func(w http.ResponseWriter, r *http.Request) {
		indexPath := filepath.Join(frontendPath, "index.html")
		http.ServeFile(w, r, indexPath)
	}).Methods("GET", "HEAD")

	// Serve static files and handle React Router client-side routing
	router.PathPrefix("/").Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Don't interfere with API routes
		if strings.HasPrefix(r.URL.Path, "/api/") {
			http.NotFound(w, r)
			return
		}
		// Clean the path to prevent directory traversal
		path := filepath.Clean(r.URL.Path)
		// Check if file exists
		filePath := filepath.Join(frontendPath, path)
		if fileInfo, err := os.Stat(filePath); err == nil && !fileInfo.IsDir() {
			// File exists and is not a directory, serve it directly
			http.ServeFile(w, r, filePath)
			return
		}
		// File doesn't exist or is a directory, serve index.html for client-side routing
		indexPath := filepath.Join(frontendPath, "index.html")
		http.ServeFile(w, r, indexPath)
	}))

	// TLS configuration (strict)
	tlsConfig := &tls.Config{
		MinVersion:               tls.VersionTLS13,
		CurvePreferences:         []tls.CurveID{tls.CurveP521, tls.CurveP384, tls.CurveP256},
		PreferServerCipherSuites: true,
		CipherSuites: []uint16{
			tls.TLS_AES_256_GCM_SHA384,
			tls.TLS_AES_128_GCM_SHA256,
			tls.TLS_CHACHA20_POLY1305_SHA256,
		},
	}

	// Create HTTPS server
	srv := &http.Server{
		Addr:         ServerAddr,
		Handler:      router,
		TLSConfig:    tlsConfig,
		ReadTimeout:  ReadTimeout,
		WriteTimeout: WriteTimeout,
		IdleTimeout:  IdleTimeout,
	}

	// Start server in goroutine
	go func() {
		logger.Printf("Starting HTTPS server on %s", ServerAddr)

		// Get TLS cert/key paths from environment, with fallback to defaults
		certPath := os.Getenv("TLS_CERT_PATH")
		keyPath := os.Getenv("TLS_KEY_PATH")

		if certPath == "" || keyPath == "" {
			// Default paths: try /app/certs (container), then certs/ (local with WORKDIR=/app), then ../certs (local dev)
			certPath = "/app/certs/server.crt"
			keyPath = "/app/certs/server.key"
			if _, err := os.Stat(certPath); os.IsNotExist(err) {
				certPath = "certs/server.crt"
				keyPath = "certs/server.key"
				if _, err := os.Stat(certPath); os.IsNotExist(err) {
					certPath = "../certs/server.crt"
					keyPath = "../certs/server.key"
				}
			}
		}

		logger.Printf("Using TLS certificate: %s", certPath)
		logger.Printf("Using TLS key: %s", keyPath)

		// Verify cert and key are readable before attempting to start server
		if _, err := os.Stat(certPath); err != nil {
			logger.Fatalf("Cannot access TLS certificate at %s: %v", certPath, err)
		}
		if _, err := os.Stat(keyPath); err != nil {
			logger.Fatalf("Cannot access TLS key at %s: %v", keyPath, err)
		}

		if err := srv.ListenAndServeTLS(certPath, keyPath); err != nil && err != http.ErrServerClosed {
			logger.Fatalf("Server failed to start: %v", err)
		}
	}()

	logger.Println("Server started successfully")

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), ShutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Fatalf("Server forced to shutdown: %v", err)
	}

	logger.Println("Server exited cleanly")
}
