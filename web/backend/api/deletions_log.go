package api

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"storage-sage/internal/config"
	"storage-sage/internal/database"
	"storage-sage/web/backend/auth"
	"storage-sage/web/backend/middleware"
)

// DeletionLogEntry represents a single deletion log entry
type DeletionLogEntry struct {
	Timestamp      time.Time `json:"timestamp"`
	Action         string    `json:"action"` // DELETE, SKIP, ERROR, DRY_RUN
	Path           string    `json:"path"`
	FileName       string    `json:"file_name"`
	ObjectType     string    `json:"object_type"` // file, directory, empty_directory
	Size           int64     `json:"size"`
	DeletionReason string    `json:"deletion_reason"`
	HumanReason    string    `json:"human_reason"`
	PrimaryReason  string    `json:"primary_reason"` // age_threshold, disk_threshold, combined, stacked_cleanup
	PathRule       string    `json:"path_rule"`
	ErrorMessage   string    `json:"error_message,omitempty"`
}

// DeletionsLogResponse is the API response for deletion log
type DeletionsLogResponse struct {
	Entries    []DeletionLogEntry `json:"entries"`
	TotalCount int                `json:"total_count"`
	PageSize   int                `json:"page_size"`
	Page       int                `json:"page"`
	HasMore    bool               `json:"has_more"`
}

// convertDBRecord converts database.DeletionRecord to API DeletionLogEntry
func convertDBRecord(record database.DeletionRecord) DeletionLogEntry {
	entry := DeletionLogEntry{
		Timestamp:      record.Timestamp,
		Action:         record.Action,
		Path:           record.Path,
		FileName:       record.FileName,
		ObjectType:     record.ObjectType,
		Size:           record.Size,
		DeletionReason: record.DeletionReason,
		PrimaryReason:  record.PrimaryReason,
		PathRule:       record.PathRule,
		ErrorMessage:   record.ErrorMessage,
	}

	// Generate human-readable reason
	entry.HumanReason = toHumanReason(record.DeletionReason, record.PrimaryReason)

	return entry
}

// toHumanReason converts technical reason to human-readable format
func toHumanReason(reason, primaryReason string) string {
	if reason == "" {
		switch primaryReason {
		case "age_threshold":
			return "File older than configured age threshold"
		case "disk_threshold":
			return "Disk usage exceeded threshold"
		case "stacked_cleanup":
			return "Critical disk usage condition"
		case "combined":
			return "Multiple conditions met"
		default:
			return "Unknown reason"
		}
	}

	// Parse structured reason string if available
	// Format examples:
	// "age_threshold: 10d (max=7d)"
	// "disk_threshold: disk_usage=95.0% (max=90.0%)"
	// "stacked_cleanup: disk_usage=99.0% (threshold=98.0%), age=20d (min=14d)"

	if primaryReason == "stacked_cleanup" {
		// Try to extract disk usage and age from reason string
		return fmt.Sprintf("Critical disk usage condition: %s", reason)
	}

	parts := []string{}

	// Check for age threshold
	if primaryReason == "age_threshold" || primaryReason == "combined" {
		parts = append(parts, "File exceeded age limit")
	}

	// Check for disk threshold
	if primaryReason == "disk_threshold" || primaryReason == "combined" {
		parts = append(parts, "Disk usage exceeded threshold")
	}

	if len(parts) > 0 {
		return fmt.Sprintf("%s: %s", reason, parts[0])
	}

	return reason
}

// GetDeletionsLogHandler handles GET /api/v1/deletions/log
func GetDeletionsLogHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetClaims(r)
	if !ok || !auth.HasPermission(claims.Roles, auth.PermissionViewLogs) {
		respondError(w, "unauthorized", http.StatusForbidden)
		return
	}

	// Parse query parameters
	limit := 100                             // default
	page := 1                                // default
	action := r.URL.Query().Get("action")    // Filter by action (DELETE, SKIP, ERROR)
	reason := r.URL.Query().Get("reason")    // Filter by primary reason
	pathPattern := r.URL.Query().Get("path") // Filter by path pattern

	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.Atoi(lStr); err == nil && l > 0 && l <= 1000 {
			limit = l
		}
	}
	if pStr := r.URL.Query().Get("page"); pStr != "" {
		if p, err := strconv.Atoi(pStr); err == nil && p > 0 {
			page = p
		}
	}

	// Determine database path
	dbPath := getDatabasePath()
	if dbPath == "" {
		// Fallback to log file parsing if database not available
		fallbackToLogFile(w, limit, page)
		return
	}

	// Open database connection
	db, err := database.NewDeletionDB(dbPath)
	if err != nil {
		log.Printf("[GetDeletionsLogHandler] Failed to open database: %v, falling back to log file", err)
		fallbackToLogFile(w, limit, page)
		return
	}
	defer db.Close()

	// Calculate offset for SQL
	offset := (page - 1) * limit

	// Query database with proper SQL pagination
	var records []database.DeletionRecord
	var totalCount int
	// err is already declared above, no need to redeclare

	if action != "" {
		records, totalCount, err = db.GetDeletionsByActionPaginated(action, limit, offset)
	} else if reason != "" {
		records, totalCount, err = db.GetDeletionsByReasonPaginated(reason, limit, offset)
	} else if pathPattern != "" {
		records, totalCount, err = db.GetDeletionsByPathPaginated(pathPattern, limit, offset)
	} else {
		records, totalCount, err = db.GetRecentDeletionsPaginated(limit, offset)
	}

	if err != nil {
		log.Printf("[GetDeletionsLogHandler] Database query error: %v", err)
		respondError(w, fmt.Sprintf("failed to query database: %v", err), http.StatusInternalServerError)
		return
	}

	// Calculate hasMore
	hasMore := offset+limit < totalCount

	// Convert to API format
	entries := make([]DeletionLogEntry, len(records))
	for i, record := range records {
		entries[i] = convertDBRecord(record)
	}

	response := DeletionsLogResponse{
		Entries:    entries,
		TotalCount: totalCount, // Use actual total from database
		PageSize:   limit,
		Page:       page,
		HasMore:    hasMore,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// getDatabasePath determines the database path from config or default
func getDatabasePath() string {
	configPath := "/etc/storage-sage/config.yaml"

	// Try to load config to get database path
	cfg, err := config.Load(configPath)
	if err == nil && cfg.DatabasePath != "" {
		return cfg.DatabasePath
	}

	// Default path
	defaultPath := "/var/lib/storage-sage/deletions.db"
	if _, err := os.Stat(defaultPath); err == nil {
		return defaultPath
	}

	// Check if directory exists but file doesn't (will be created)
	dir := filepath.Dir(defaultPath)
	if _, err := os.Stat(dir); err == nil {
		return defaultPath
	}

	return ""
}

// fallbackToLogFile falls back to log file parsing if database unavailable
func fallbackToLogFile(w http.ResponseWriter, limit, page int) {
	logPath := "/var/log/storage-sage/cleanup.log"
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		logPath = "/app/logs/cleanup.log"
	}

	// Use existing LogParser as fallback
	parser := NewLogParser(logPath)
	offset := (page - 1) * limit

	entries, err := parser.ParseLog(limit, offset)
	if err != nil {
		respondError(w, fmt.Sprintf("failed to parse log file: %v", err), http.StatusInternalServerError)
		return
	}

	response := DeletionsLogResponse{
		Entries:    entries,
		TotalCount: len(entries),
		PageSize:   limit,
		Page:       page,
		HasMore:    false, // Can't determine with log file
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// Keep LogParser for fallback compatibility
type LogParser struct {
	logPath string
}

func NewLogParser(logPath string) *LogParser {
	return &LogParser{logPath: logPath}
}

// ParseLog reads and parses the cleanup log file
func (lp *LogParser) ParseLog(limit int, offset int) ([]DeletionLogEntry, error) {
	file, err := os.Open(lp.logPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open log file: %w", err)
	}
	defer file.Close()

	var entries []DeletionLogEntry
	scanner := bufio.NewScanner(file)

	// Read all lines into memory (for reverse order and pagination)
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed to read log file: %w", err)
	}

	// Reverse order (newest first)
	for i := len(lines) - 1; i >= 0; i-- {
		line := lines[i]
		entry, err := lp.parseLine(line)
		if err != nil {
			// Skip malformed lines
			continue
		}
		entries = append(entries, entry)
	}

	// Apply pagination
	start := offset
	end := offset + limit
	if start > len(entries) {
		return []DeletionLogEntry{}, nil
	}
	if end > len(entries) {
		end = len(entries)
	}

	return entries[start:end], nil
}

// parseLine parses a single log line
// Format: [2025-11-15T01:36:57Z] ACTION path=/var/log/file object=file size=1024 deletion_reason="age_threshold: 10d (max=7d)"
func (lp *LogParser) parseLine(line string) (DeletionLogEntry, error) {
	entry := DeletionLogEntry{}

	// Regex to parse structured log format
	// Captures: timestamp, action, path, object, size, deletion_reason, legacy reason
	re := regexp.MustCompile(`\[([^\]]+)\]\s+(\w+)\s+path=([^\s]+)\s+object=([^\s]+)\s+size=(\d+)(?:\s+deletion_reason="([^"]*)")?(?:\s+reason=([^\s]+))?`)
	matches := re.FindStringSubmatch(line)

	if len(matches) < 6 {
		return entry, fmt.Errorf("malformed log line")
	}

	// Parse timestamp
	timestamp, err := time.Parse(time.RFC3339, matches[1])
	if err != nil {
		return entry, fmt.Errorf("invalid timestamp: %w", err)
	}

	// Parse size
	size, err := strconv.ParseInt(matches[5], 10, 64)
	if err != nil {
		return entry, fmt.Errorf("invalid size: %w", err)
	}

	entry.Timestamp = timestamp
	entry.Action = matches[2]
	entry.Path = matches[3]
	entry.FileName = filepath.Base(matches[3])
	entry.ObjectType = matches[4]
	entry.Size = size

	// Parse deletion reason (optional field)
	if len(matches) > 6 && matches[6] != "" {
		entry.DeletionReason = matches[6]
		entry.HumanReason = lp.toHumanReason(matches[6])
		entry.PrimaryReason = lp.extractPrimaryReason(matches[6])
	} else {
		// Legacy reason= fallback (e.g., reason=file, reason=directory, reason=empty_directory)
		if len(matches) >= 8 && matches[7] != "" {
			legacy := matches[7]
			entry.DeletionReason = legacy
			switch legacy {
			case "empty_directory":
				entry.HumanReason = "Empty directory"
			case "directory":
				entry.HumanReason = "Directory removed"
			case "file":
				entry.HumanReason = "File removed"
			default:
				entry.HumanReason = "Unknown reason"
			}
			entry.PrimaryReason = "legacy"
			// For legacy lines, object field is often the filename; adjust object_type to the legacy kind
			if entry.ObjectType == entry.FileName {
				entry.ObjectType = legacy
			}
		} else {
			entry.DeletionReason = ""
			entry.HumanReason = "Unknown reason"
			entry.PrimaryReason = "unknown"
		}
	}

	return entry, nil
}

// toHumanReason converts technical reason to human-readable format
func (lp *LogParser) toHumanReason(reason string) string {
	// Check for stacked cleanup first (highest priority)
	if strings.Contains(reason, "stacked_cleanup:") {
		// Example: "stacked_cleanup: disk_usage=99.0% (threshold=98.0%), age=20d (min=14d)"
		re := regexp.MustCompile(`disk_usage=([\d.]+)%.*age=(\d+)d`)
		matches := re.FindStringSubmatch(reason)
		if len(matches) >= 3 {
			diskUsage, _ := strconv.ParseFloat(matches[1], 64)
			ageDays, _ := strconv.ParseFloat(matches[2], 64)
			return fmt.Sprintf("Critical disk usage (%.1f%%), file %.0f days old", diskUsage, ageDays)
		}
		return "Critical disk usage condition"
	}

	var parts []string

	// Disk threshold
	if strings.Contains(reason, "disk_threshold:") {
		re := regexp.MustCompile(`disk_threshold:.*\(max=([\d.]+)%\)`)
		matches := re.FindStringSubmatch(reason)
		if len(matches) >= 2 {
			threshold := matches[1]
			parts = append(parts, fmt.Sprintf("Disk usage exceeded %s%%", threshold))
		}
	}

	// Age threshold
	if strings.Contains(reason, "age_threshold:") {
		re := regexp.MustCompile(`age_threshold:.*\(max=(\d+)d\)`)
		matches := re.FindStringSubmatch(reason)
		if len(matches) >= 2 {
			days := matches[1]
			parts = append(parts, fmt.Sprintf("File older than %s days", days))
		}
	}

	if len(parts) > 0 {
		return strings.Join(parts, ", ")
	}

	return "Unknown reason"
}

// extractPrimaryReason determines the primary category
func (lp *LogParser) extractPrimaryReason(reason string) string {
	if strings.Contains(reason, "stacked_cleanup:") {
		return "stacked_cleanup"
	}

	hasDisk := strings.Contains(reason, "disk_threshold:")
	hasAge := strings.Contains(reason, "age_threshold:")

	if hasDisk && hasAge {
		return "combined"
	}
	if hasDisk {
		return "disk_threshold"
	}
	if hasAge {
		return "age_threshold"
	}

	return "unknown"
}
