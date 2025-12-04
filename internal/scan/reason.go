package scan

import (
	"fmt"
	"strings"
	"time"
)

// DeletionReason captures why a file was selected for deletion.
// Multiple reasons can apply simultaneously (e.g., both age and disk threshold).
type DeletionReason struct {
	// Primary reasons (nil if not applicable)
	AgeThreshold   *AgeReason
	DiskThreshold  *DiskReason
	StackedCleanup *StackedReason

	// Metadata
	PathRule    string    // Which PathRule triggered this (e.g., "/var/log")
	EvaluatedAt time.Time // When conditions were checked
}

// AgeReason indicates file was selected due to age threshold.
type AgeReason struct {
	ConfiguredDays int // age_off_days from config
	ActualAgeDays  int // actual file age at scan time
}

// DiskReason indicates file was selected due to disk usage threshold.
type DiskReason struct {
	ConfiguredPercent float64 // max_free_percent from config
	ActualPercent     float64 // actual disk usage at scan time
}

// StackedReason indicates file was selected due to stacked cleanup (emergency mode).
type StackedReason struct {
	StackThreshold float64 // stack_threshold from config
	StackAgeDays   int     // stack_age_days from config
	ActualPercent  float64 // actual disk usage at scan time
	ActualAgeDays  int     // actual file age at scan time
}

// HasReason returns true if any deletion reason applies.
func (dr DeletionReason) HasReason() bool {
	return dr.AgeThreshold != nil || dr.DiskThreshold != nil || dr.StackedCleanup != nil
}

// ToLogString formats the reason for structured logging.
// Example: "stacked_cleanup: disk_usage=99.0% (threshold=98.0%), age=20d (min=14d) + disk_threshold: 99.0% (max=90.0%) + age_threshold: 20d (max=7d)"
func (dr DeletionReason) ToLogString() string {
	if !dr.HasReason() {
		return "unknown"
	}

	var parts []string

	// Show in priority order: stacked > disk > age
	if dr.StackedCleanup != nil {
		parts = append(parts, fmt.Sprintf(
			"stacked_cleanup: disk_usage=%.1f%% (threshold=%.1f%%), age=%dd (min=%dd)",
			dr.StackedCleanup.ActualPercent,
			dr.StackedCleanup.StackThreshold,
			dr.StackedCleanup.ActualAgeDays,
			dr.StackedCleanup.StackAgeDays,
		))
	}

	if dr.DiskThreshold != nil {
		parts = append(parts, fmt.Sprintf(
			"disk_threshold: %.1f%% (max=%.1f%%)",
			dr.DiskThreshold.ActualPercent,
			dr.DiskThreshold.ConfiguredPercent,
		))
	}

	if dr.AgeThreshold != nil {
		parts = append(parts, fmt.Sprintf(
			"age_threshold: %dd (max=%dd)",
			dr.AgeThreshold.ActualAgeDays,
			dr.AgeThreshold.ConfiguredDays,
		))
	}

	return strings.Join(parts, " + ")
}

// ToHumanReadable formats the reason for UI display.
// Example: "Critical disk usage (99.0%), file 20 days old"
func (dr DeletionReason) ToHumanReadable() string {
	if !dr.HasReason() {
		return "Unknown reason"
	}

	var parts []string

	// If stacked cleanup is active, prioritize that message
	if dr.StackedCleanup != nil {
		parts = append(parts, fmt.Sprintf(
			"Critical disk usage (%.1f%%), file %d days old",
			dr.StackedCleanup.ActualPercent,
			dr.StackedCleanup.ActualAgeDays,
		))
	} else {
		// Show individual reasons only if not in stacked mode
		if dr.DiskThreshold != nil {
			parts = append(parts, fmt.Sprintf(
				"Disk usage exceeded %.1f%%",
				dr.DiskThreshold.ConfiguredPercent,
			))
		}

		if dr.AgeThreshold != nil {
			parts = append(parts, fmt.Sprintf(
				"File older than %d days",
				dr.AgeThreshold.ConfiguredDays,
			))
		}
	}

	return strings.Join(parts, ", ")
}

// GetPrimaryReason returns a short label for the most critical reason.
// Used for filtering/grouping in the UI.
func (dr DeletionReason) GetPrimaryReason() string {
	if dr.StackedCleanup != nil {
		return "stacked_cleanup"
	}
	if dr.DiskThreshold != nil && dr.AgeThreshold != nil {
		return "combined"
	}
	if dr.DiskThreshold != nil {
		return "disk_threshold"
	}
	if dr.AgeThreshold != nil {
		return "age_threshold"
	}
	return "unknown"
}
