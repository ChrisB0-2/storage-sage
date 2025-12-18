package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"text/tabwriter"

	"storage-sage/internal/database"
	"storage-sage/internal/exitcodes"
)

func main() {
	// Parse command-line flags
	dbPath := flag.String("db", "/var/lib/storage-sage/deletions.db", "Path to deletion database")
	recent := flag.Int("recent", 0, "Show N most recent deletions")
	stats := flag.Bool("stats", false, "Show deletion statistics")
	reason := flag.String("reason", "", "Filter by deletion reason")
	action := flag.String("action", "", "Filter by action (DELETE, SKIP, ERROR)")
	pathPattern := flag.String("path", "", "Filter by path pattern (SQL LIKE syntax)")
	largest := flag.Int("largest", 0, "Show N largest deletions")
	days := flag.Int("days", 30, "Number of days for statistics (default: 30)")
	jsonOutput := flag.Bool("json", false, "Output in JSON format")
	flag.Parse()

	// Open database
	db, err := database.NewDeletionDB(*dbPath)
	if err != nil {
		log.Fatalf("ERROR: Failed to open database %s: %v", *dbPath, err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			log.Printf("ERROR: Failed to close database: %v", err)
		}
	}()

	// Handle different query modes
	switch {
	case *stats:
		showStats(db, *days, *jsonOutput)
	case *recent > 0:
		showRecent(db, *recent, *jsonOutput)
	case *reason != "":
		showByReason(db, *reason, *jsonOutput)
	case *action != "":
		showByAction(db, *action, *jsonOutput)
	case *pathPattern != "":
		showByPath(db, *pathPattern, *jsonOutput)
	case *largest > 0:
		showLargest(db, *largest, *jsonOutput)
	default:
		flag.Usage()
		fmt.Println("\nExamples:")
		fmt.Println("  storage-sage-query --recent 10           # Show 10 most recent deletions")
		fmt.Println("  storage-sage-query --stats               # Show deletion statistics")
		fmt.Println("  storage-sage-query --reason AGE          # Show deletions by age")
		fmt.Println("  storage-sage-query --action DELETE       # Show only deletions")
		fmt.Println("  storage-sage-query --path '/var/log/%'   # Show deletions from /var/log")
		fmt.Println("  storage-sage-query --largest 10          # Show 10 largest deletions")
		os.Exit(exitcodes.InvalidConfig)
	}
}

func showStats(db *database.DeletionDB, days int, jsonOutput bool) {
	stats, err := db.GetDeletionStats(days)
	if err != nil {
		log.Fatalf("ERROR: Failed to get statistics: %v", err)
	}

	if jsonOutput {
		data, _ := json.MarshalIndent(stats, "", "  ")
		fmt.Println(string(data))
		return
	}

	fmt.Printf("Deletion Statistics (Last %d days)\n", days)
	fmt.Printf("Period: %s to %s\n\n", stats.StartDate.Format("2006-01-02"), stats.EndDate.Format("2006-01-02"))
	fmt.Printf("Total Deletions:  %d\n", stats.TotalDeletions)
	fmt.Printf("Total Skipped:    %d\n", stats.TotalSkipped)
	fmt.Printf("Total Errors:     %d\n", stats.TotalErrors)
	fmt.Printf("Space Freed:      %s\n\n", formatBytes(stats.TotalSpaceFreed))

	if len(stats.ByReason) > 0 {
		fmt.Println("By Reason:")
		for reason, count := range stats.ByReason {
			fmt.Printf("  %-15s %d\n", reason, count)
		}
		fmt.Println()
	}

	if len(stats.ByAction) > 0 {
		fmt.Println("By Action:")
		for action, count := range stats.ByAction {
			fmt.Printf("  %-15s %d\n", action, count)
		}
	}
}

func showRecent(db *database.DeletionDB, limit int, jsonOutput bool) {
	records, err := db.GetRecentDeletions(limit)
	if err != nil {
		log.Fatalf("ERROR: Failed to get recent deletions: %v", err)
	}

	if jsonOutput {
		data, _ := json.MarshalIndent(records, "", "  ")
		fmt.Println(string(data))
		return
	}

	printRecords(records)
}

func showByReason(db *database.DeletionDB, reason string, jsonOutput bool) {
	records, err := db.GetDeletionsByReason(reason)
	if err != nil {
		log.Fatalf("ERROR: Failed to query by reason: %v", err)
	}

	if jsonOutput {
		data, _ := json.MarshalIndent(records, "", "  ")
		fmt.Println(string(data))
		return
	}

	fmt.Printf("Deletions with reason: %s\n\n", reason)
	printRecords(records)
}

func showByAction(db *database.DeletionDB, action string, jsonOutput bool) {
	records, err := db.GetDeletionsByAction(action)
	if err != nil {
		log.Fatalf("ERROR: Failed to query by action: %v", err)
	}

	if jsonOutput {
		data, _ := json.MarshalIndent(records, "", "  ")
		fmt.Println(string(data))
		return
	}

	fmt.Printf("Records with action: %s\n\n", action)
	printRecords(records)
}

func showByPath(db *database.DeletionDB, pathPattern string, jsonOutput bool) {
	records, err := db.GetDeletionsByPath(pathPattern)
	if err != nil {
		log.Fatalf("ERROR: Failed to query by path: %v", err)
	}

	if jsonOutput {
		data, _ := json.MarshalIndent(records, "", "  ")
		fmt.Println(string(data))
		return
	}

	fmt.Printf("Deletions matching path pattern: %s\n\n", pathPattern)
	printRecords(records)
}

func showLargest(db *database.DeletionDB, limit int, jsonOutput bool) {
	records, err := db.GetLargestDeletions(limit)
	if err != nil {
		log.Fatalf("ERROR: Failed to get largest deletions: %v", err)
	}

	if jsonOutput {
		data, _ := json.MarshalIndent(records, "", "  ")
		fmt.Println(string(data))
		return
	}

	fmt.Printf("Largest %d deletions:\n\n", limit)
	printRecords(records)
}

func printRecords(records []database.DeletionRecord) {
	if len(records) == 0 {
		fmt.Println("No records found")
		return
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	_, _ = fmt.Fprintln(w, "ID\tTimestamp\tAction\tReason\tSize\tPath")
	_, _ = fmt.Fprintln(w, "--\t---------\t------\t------\t----\t----")

	for _, r := range records {
		timestamp := r.Timestamp.Format("2006-01-02 15:04:05")
		size := formatBytes(r.Size)
		fullPath := r.Path
		if r.FileName != "" {
			fullPath = fullPath + "/" + r.FileName
		}
		_, _ = fmt.Fprintf(w, "%d\t%s\t%s\t%s\t%s\t%s\n",
			r.ID, timestamp, r.Action, r.PrimaryReason, size, fullPath)
	}
	_ = w.Flush()
}

func formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}
