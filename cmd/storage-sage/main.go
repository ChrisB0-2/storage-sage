package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"storage-sage/internal/config"
	"storage-sage/internal/database"
	"storage-sage/internal/exitcodes"
	"storage-sage/internal/logging"
	"storage-sage/internal/metrics"
	"storage-sage/internal/scheduler"
)

func main() {
	// Parse command-line flags
	configPath := flag.String("config", "/etc/storage-sage/config.yaml", "Path to configuration file")
	dryRun := flag.Bool("dry-run", false, "Perform dry run without deleting files")
	once := flag.Bool("once", false, "Run cleanup once and exit (no loop)")
	flag.Parse()

	// Initialize logger
	logger := logging.New()

	logger.Println("Storage Sage Daemon Starting...")
	logger.Printf("Config file: %s", *configPath)
	if *dryRun {
		logger.Println("DRY RUN MODE: No files will be deleted")
	}

	// Load configuration
	cfg, err := config.Load(*configPath)
	if err != nil {
		logger.Printf("ERROR: Failed to load config: %v", err)
		os.Exit(exitcodes.InvalidConfig)
	}

	// Initialize metrics (Prometheus)
	metrics.Init()
	if cfg.Prometheus.Port > 0 {
		addr := fmt.Sprintf(":%d", cfg.Prometheus.Port)
		logger.Printf("Starting Prometheus metrics on %s", addr)
		metrics.StartServer(addr, logger)
	}

	// Initialize database for deletion history
	var db *database.DeletionDB
	if cfg.DatabasePath != "" {
		logger.Printf("Opening deletion database: %s", cfg.DatabasePath)
		db, err = database.NewDeletionDB(cfg.DatabasePath)
		if err != nil {
			logger.Printf("ERROR: Failed to open database: %v", err)
			os.Exit(exitcodes.RuntimeError)
		}
		defer func() {
			if err := db.Close(); err != nil {
				logger.Printf("ERROR: Failed to close database: %v", err)
			}
		}()
	}

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigChan
		logger.Printf("Received signal %v, shutting down gracefully...", sig)
		cancel()
	}()

	// Run scheduler
	logger.Println("Starting cleanup scheduler...")
	if *once {
		// Run once and exit
		if err := scheduler.RunOnceWithDB(ctx, cfg, *dryRun, logger, db); err != nil {
			logger.Printf("ERROR: Cleanup failed: %v", err)
			os.Exit(exitcodes.RuntimeError)
		}
		logger.Println("Cleanup completed successfully")
	} else {
		// Run continuously with database support
		if err := scheduler.RunWithDB(ctx, cfg, *dryRun, logger, db); err != nil && err != context.Canceled {
			logger.Printf("ERROR: Scheduler failed: %v", err)
			os.Exit(exitcodes.RuntimeError)
		}
	}

	logger.Println("Storage Sage Daemon stopped")
}
