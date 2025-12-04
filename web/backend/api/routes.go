package api

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"storage-sage/internal/config"
	"storage-sage/web/backend/auth"
	"storage-sage/web/backend/middleware"

	"gopkg.in/yaml.v3"
)

// LoginRequest represents login credentials
type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// LoginResponse contains JWT token
type LoginResponse struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	User      UserInfo  `json:"user"`
}

// UserInfo contains user details
type UserInfo struct {
	Username string   `json:"username"`
	Roles    []string `json:"roles"`
}

// ErrorResponse represents error message
type ErrorResponse struct {
	Error   string `json:"error"`
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// LoginHandler handles user authentication
func LoginHandler(jwtManager *auth.JWTManager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req LoginRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			respondError(w, "invalid request body", http.StatusBadRequest)
			return
		}

		// CRITICAL: Replace with real authentication against secure user database
		// This is a simplified example - NEVER use hardcoded credentials in production
		if req.Username != "admin" || req.Password != "changeme" {
			respondError(w, "invalid credentials", http.StatusUnauthorized)
			return
		}

		// Assign roles based on user (fetch from database in production)
		roles := []string{auth.RoleAdmin}

		token, err := jwtManager.GenerateToken("user-id-1", req.Username, roles)
		if err != nil {
			respondError(w, "failed to generate token", http.StatusInternalServerError)
			return
		}

		response := LoginResponse{
			Token:     token,
			ExpiresAt: time.Now().Add(24 * time.Hour),
			User: UserInfo{
				Username: req.Username,
				Roles:    roles,
			},
		}

		respondJSON(w, response, http.StatusOK)
	}
}

// HealthHandler returns server health status
func HealthHandler(w http.ResponseWriter, r *http.Request) {
	// Ensure security headers are present (defensive approach - middleware should set these,
	// but we verify they're set to guarantee compliance for this critical endpoint)
	if w.Header().Get("X-Content-Type-Options") == "" {
		w.Header().Set("X-Content-Type-Options", "nosniff")
	}
	if w.Header().Get("X-Frame-Options") == "" {
		w.Header().Set("X-Frame-Options", "DENY")
	}
	if w.Header().Get("Strict-Transport-Security") == "" {
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
	}

	// Set Content-Type for both GET and HEAD requests
	w.Header().Set("Content-Type", "application/json")

	// For HEAD requests, only send headers (no body)
	if r.Method == http.MethodHead {
		w.WriteHeader(http.StatusOK)
		return
	}

	// For GET requests, send full JSON response
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

// GetConfigHandler returns current configuration
func GetConfigHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetClaims(r)
	if !ok || !auth.HasPermission(claims.Roles, auth.PermissionViewConfig) {
		respondError(w, "unauthorized", http.StatusForbidden)
		return
	}

	configPath := "/etc/storage-sage/config.yaml"

	// Try to load config directly (no sudo needed in Docker)
	cfg, err := config.Load(configPath)
	if err != nil {
		// If config doesn't exist, return default/empty config
		if os.IsNotExist(err) {
			// Return minimal valid config structure
			cfg := &config.Config{
				ScanPaths:       []string{},
				AgeOffDays:      7,
				MinFreePercent:  10,
				IntervalMinutes: 15,
				Prometheus: config.PrometheusCfg{
					Port: 9090,
				},
			}
			respondJSON(w, cfg, http.StatusOK)
			return
		}
		respondError(w, fmt.Sprintf("failed to load config: %v", err), http.StatusInternalServerError)
		return
	}

	respondJSON(w, cfg, http.StatusOK)
}

// UpdateConfigHandler updates configuration
func UpdateConfigHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetClaims(r)
	if !ok || !auth.HasPermission(claims.Roles, auth.PermissionEditConfig) {
		respondError(w, "unauthorized", http.StatusForbidden)
		return
	}

	var cfg config.Config
	if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
		respondError(w, "invalid config format", http.StatusBadRequest)
		return
	}

	// Marshal config to YAML
	yamlData, err := yaml.Marshal(&cfg)
	if err != nil {
		respondError(w, fmt.Sprintf("failed to marshal config: %v", err), http.StatusInternalServerError)
		return
	}

	// Write to temporary file first for validation
	tmpFile, err := os.CreateTemp("", "storage-sage-config-*.yaml")
	if err != nil {
		respondError(w, fmt.Sprintf("failed to create temp file: %v", err), http.StatusInternalServerError)
		return
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.Write(yamlData); err != nil {
		tmpFile.Close()
		respondError(w, fmt.Sprintf("failed to write temp file: %v", err), http.StatusInternalServerError)
		return
	}
	tmpFile.Close()

	// Validate the config by loading it
	_, err = config.Load(tmpFile.Name())
	if err != nil {
		respondError(w, fmt.Sprintf("invalid config: %v", err), http.StatusBadRequest)
		return
	}

	// Ensure config directory exists
	configDir := "/etc/storage-sage"
	if err := os.MkdirAll(configDir, 0755); err != nil {
		respondError(w, fmt.Sprintf("failed to create config directory: %v", err), http.StatusInternalServerError)
		return
	}

	// Write to final location directly (no sudo needed in Docker)
	configPath := "/etc/storage-sage/config.yaml"
	if err := os.WriteFile(configPath, yamlData, 0644); err != nil {
		respondError(w, fmt.Sprintf("failed to write config file: %v", err), http.StatusInternalServerError)
		return
	}

	// Trigger config reload on daemon via HTTP endpoint
	daemonURL := os.Getenv("DAEMON_METRICS_URL")
	if daemonURL == "" {
		daemonURL = "http://storage-sage-daemon:9090"
	}

	reloadURL := daemonURL + "/reload"
	log.Printf("[UpdateConfigHandler] Triggering config reload on daemon: %s", reloadURL)

	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	resp, err := client.Post(reloadURL, "application/json", nil)
	if err != nil {
		log.Printf("[UpdateConfigHandler] WARNING: Failed to trigger reload: %v (config saved but daemon may need manual restart)", err)
		// Don't fail the request - config is saved, daemon will pick it up on next restart
		respondJSON(w, map[string]string{
			"message": "config updated successfully (daemon reload failed - may need manual restart)",
			"warning": fmt.Sprintf("failed to reload daemon: %v", err),
		}, http.StatusOK)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("[UpdateConfigHandler] WARNING: Daemon reload returned non-OK status: %d", resp.StatusCode)
		respondJSON(w, map[string]string{
			"message": "config updated successfully (daemon reload may have failed)",
			"warning": fmt.Sprintf("daemon reload returned status %d", resp.StatusCode),
		}, http.StatusOK)
		return
	}

	log.Printf("[UpdateConfigHandler] Successfully saved config and reloaded daemon")
	respondJSON(w, map[string]string{"message": "config updated and daemon reloaded successfully"}, http.StatusOK)
}

// ValidateConfigHandler validates configuration without applying
func ValidateConfigHandler(w http.ResponseWriter, r *http.Request) {
	var cfg config.Config
	if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
		respondJSON(w, map[string]interface{}{
			"valid": false,
			"error": fmt.Sprintf("invalid config format: %v", err),
		}, http.StatusBadRequest)
		return
	}

	// Marshal to YAML to test serialization
	yamlData, err := yaml.Marshal(&cfg)
	if err != nil {
		respondJSON(w, map[string]interface{}{
			"valid": false,
			"error": fmt.Sprintf("failed to marshal config: %v", err),
		}, http.StatusBadRequest)
		return
	}

	// Write to temporary file and validate by loading
	tmpFile, err := os.CreateTemp("", "storage-sage-config-validate-*.yaml")
	if err != nil {
		respondJSON(w, map[string]interface{}{
			"valid": false,
			"error": fmt.Sprintf("failed to create temp file: %v", err),
		}, http.StatusInternalServerError)
		return
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.Write(yamlData); err != nil {
		tmpFile.Close()
		respondJSON(w, map[string]interface{}{
			"valid": false,
			"error": fmt.Sprintf("failed to write temp file: %v", err),
		}, http.StatusInternalServerError)
		return
	}
	tmpFile.Close()

	// Validate by loading
	_, err = config.Load(tmpFile.Name())
	if err != nil {
		respondJSON(w, map[string]interface{}{
			"valid": false,
			"error": fmt.Sprintf("invalid config: %v", err),
		}, http.StatusBadRequest)
		return
	}

	respondJSON(w, map[string]bool{"valid": true}, http.StatusOK)
}

// GetMetricsHandler returns current metrics
func GetMetricsHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetClaims(r)
	if !ok || !auth.HasPermission(claims.Roles, auth.PermissionViewMetrics) {
		respondError(w, "unauthorized", http.StatusForbidden)
		return
	}

	// Create HTTP client with timeout to prevent hanging
	client := &http.Client{
		Timeout: 10 * time.Second, // Increased from 5 to 10 seconds
	}

	// Fetch metrics from daemon (use Docker service name, not localhost)
	daemonURL := os.Getenv("DAEMON_METRICS_URL")
	if daemonURL == "" {
		daemonURL = "http://storage-sage-daemon:9090"
	}
	
	fullURL := daemonURL + "/metrics"
	log.Printf("[GetMetricsHandler] Fetching metrics from daemon: %s", fullURL)
	
	resp, err := client.Get(fullURL)
	if err != nil {
		log.Printf("[GetMetricsHandler] ERROR: Failed to fetch metrics from daemon %s: %v", fullURL, err)
		respondError(w, fmt.Sprintf("failed to fetch metrics from daemon: %v", err), http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	// Check HTTP status
	if resp.StatusCode != http.StatusOK {
		log.Printf("[GetMetricsHandler] ERROR: Daemon returned non-OK status: %d", resp.StatusCode)
		respondError(w, fmt.Sprintf("daemon returned non-OK status: %d", resp.StatusCode), http.StatusBadGateway)
		return
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("[GetMetricsHandler] ERROR: Failed to read metrics response: %v", err)
		respondError(w, "failed to read metrics response", http.StatusInternalServerError)
		return
	}

	log.Printf("[GetMetricsHandler] Successfully fetched %d bytes from daemon", len(body))
	w.Header().Set("Content-Type", "text/plain")
	w.Write(body)
}

// GetMetricsHistoryHandler returns historical metrics
func GetMetricsHistoryHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetClaims(r)
	if !ok || !auth.HasPermission(claims.Roles, auth.PermissionViewMetrics) {
		respondError(w, "unauthorized", http.StatusForbidden)
		return
	}

	// Query Prometheus for historical data
	// This is a placeholder - implement Prometheus query API
	history := map[string]interface{}{
		"timeRange": "24h",
		"data":      []interface{}{},
	}

	respondJSON(w, history, http.StatusOK)
}

// TriggerCleanupHandler manually triggers cleanup cycle
func TriggerCleanupHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetClaims(r)
	if !ok || !auth.HasPermission(claims.Roles, auth.PermissionTriggerCleanup) {
		respondError(w, "unauthorized", http.StatusForbidden)
		return
	}

	// Create HTTP client with timeout
	client := &http.Client{
		Timeout: 10 * time.Second, // Increased from 5 to 10 seconds
	}

	// Trigger cleanup via HTTP endpoint on daemon
	daemonURL := os.Getenv("DAEMON_METRICS_URL")
	if daemonURL == "" {
		daemonURL = "http://storage-sage-daemon:9090"
	}

	triggerURL := daemonURL + "/trigger"
	log.Printf("[TriggerCleanupHandler] Triggering cleanup on daemon: %s", triggerURL)
	
	resp, err := client.Post(triggerURL, "application/json", nil)
	if err != nil {
		log.Printf("[TriggerCleanupHandler] ERROR: Failed to trigger cleanup: %v", err)
		respondError(w, fmt.Sprintf("failed to trigger cleanup: %v", err), http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("[TriggerCleanupHandler] ERROR: Daemon returned non-OK status: %d", resp.StatusCode)
		respondError(w, fmt.Sprintf("daemon returned non-OK status: %d", resp.StatusCode), http.StatusBadGateway)
		return
	}
	
	log.Printf("[TriggerCleanupHandler] Successfully triggered cleanup on daemon")

	respondJSON(w, map[string]string{
		"message": "cleanup triggered successfully",
		"status":  "running",
	}, http.StatusOK)
}

// GetCleanupStatusHandler returns cleanup status
func GetCleanupStatusHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetClaims(r)
	if !ok || !auth.HasPermission(claims.Roles, auth.PermissionViewMetrics) {
		respondError(w, "unauthorized", http.StatusForbidden)
		return
	}

	status := map[string]interface{}{
		"running":      false,
		"lastRun":      time.Now().Add(-15 * time.Minute),
		"nextRun":      time.Now().Add(15 * time.Minute),
		"filesDeleted": 0,
		"bytesFreed":   0,
	}

	respondJSON(w, status, http.StatusOK)
}

// Helper functions
func respondJSON(w http.ResponseWriter, data interface{}, status int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func respondError(w http.ResponseWriter, message string, status int) {
	respondJSON(w, ErrorResponse{
		Error:   http.StatusText(status),
		Code:    status,
		Message: message,
	}, status)
}
