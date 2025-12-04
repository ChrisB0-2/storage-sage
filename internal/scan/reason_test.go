package scan

import (
	"testing"

	"storage-sage/internal/config"
)

func TestDeletionReason_HasReason(t *testing.T) {
	tests := []struct {
		name   string
		reason DeletionReason
		want   bool
	}{
		{
			name:   "no reasons",
			reason: DeletionReason{},
			want:   false,
		},
		{
			name: "age only",
			reason: DeletionReason{
				AgeThreshold: &AgeReason{ConfiguredDays: 7, ActualAgeDays: 10},
			},
			want: true,
		},
		{
			name: "disk only",
			reason: DeletionReason{
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 92},
			},
			want: true,
		},
		{
			name: "stacked only",
			reason: DeletionReason{
				StackedCleanup: &StackedReason{
					StackThreshold: 98,
					StackAgeDays:   14,
					ActualPercent:  99,
					ActualAgeDays:  20,
				},
			},
			want: true,
		},
		{
			name: "all reasons",
			reason: DeletionReason{
				AgeThreshold:   &AgeReason{ConfiguredDays: 7, ActualAgeDays: 20},
				DiskThreshold:  &DiskReason{ConfiguredPercent: 90, ActualPercent: 99},
				StackedCleanup: &StackedReason{StackThreshold: 98, StackAgeDays: 14, ActualPercent: 99, ActualAgeDays: 20},
			},
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.reason.HasReason(); got != tt.want {
				t.Errorf("HasReason() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestDeletionReason_ToLogString(t *testing.T) {
	tests := []struct {
		name   string
		reason DeletionReason
		want   string
	}{
		{
			name: "age only",
			reason: DeletionReason{
				AgeThreshold: &AgeReason{ConfiguredDays: 7, ActualAgeDays: 10},
			},
			want: "age_threshold: 10d (max=7d)",
		},
		{
			name: "disk only",
			reason: DeletionReason{
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 92.5},
			},
			want: "disk_threshold: 92.5% (max=90.0%)",
		},
		{
			name: "combined age and disk",
			reason: DeletionReason{
				AgeThreshold:  &AgeReason{ConfiguredDays: 7, ActualAgeDays: 10},
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 92.5},
			},
			want: "disk_threshold: 92.5% (max=90.0%) + age_threshold: 10d (max=7d)",
		},
		{
			name: "stacked cleanup (all three)",
			reason: DeletionReason{
				StackedCleanup: &StackedReason{
					StackThreshold: 98,
					StackAgeDays:   14,
					ActualPercent:  99.2,
					ActualAgeDays:  20,
				},
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 99.2},
				AgeThreshold:  &AgeReason{ConfiguredDays: 7, ActualAgeDays: 20},
			},
			want: "stacked_cleanup: disk_usage=99.2% (threshold=98.0%), age=20d (min=14d) + disk_threshold: 99.2% (max=90.0%) + age_threshold: 20d (max=7d)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.reason.ToLogString()
			if got != tt.want {
				t.Errorf("ToLogString() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestDeletionReason_ToHumanReadable(t *testing.T) {
	tests := []struct {
		name   string
		reason DeletionReason
		want   string
	}{
		{
			name: "age only",
			reason: DeletionReason{
				AgeThreshold: &AgeReason{ConfiguredDays: 7, ActualAgeDays: 10},
			},
			want: "File older than 7 days",
		},
		{
			name: "disk only",
			reason: DeletionReason{
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 92.5},
			},
			want: "Disk usage exceeded 90.0%",
		},
		{
			name: "combined age and disk",
			reason: DeletionReason{
				AgeThreshold:  &AgeReason{ConfiguredDays: 7, ActualAgeDays: 10},
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 92.5},
			},
			want: "Disk usage exceeded 90.0%, File older than 7 days",
		},
		{
			name: "stacked cleanup (priority message)",
			reason: DeletionReason{
				StackedCleanup: &StackedReason{
					StackThreshold: 98,
					StackAgeDays:   14,
					ActualPercent:  99.2,
					ActualAgeDays:  20,
				},
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 99.2},
				AgeThreshold:  &AgeReason{ConfiguredDays: 7, ActualAgeDays: 20},
			},
			want: "Critical disk usage (99.2%), file 20 days old",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.reason.ToHumanReadable()
			if got != tt.want {
				t.Errorf("ToHumanReadable() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestDeletionReason_GetPrimaryReason(t *testing.T) {
	tests := []struct {
		name   string
		reason DeletionReason
		want   string
	}{
		{
			name:   "no reason",
			reason: DeletionReason{},
			want:   "unknown",
		},
		{
			name: "age only",
			reason: DeletionReason{
				AgeThreshold: &AgeReason{ConfiguredDays: 7, ActualAgeDays: 10},
			},
			want: "age_threshold",
		},
		{
			name: "disk only",
			reason: DeletionReason{
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 92},
			},
			want: "disk_threshold",
		},
		{
			name: "combined (both age and disk)",
			reason: DeletionReason{
				AgeThreshold:  &AgeReason{ConfiguredDays: 7, ActualAgeDays: 10},
				DiskThreshold: &DiskReason{ConfiguredPercent: 90, ActualPercent: 92},
			},
			want: "combined",
		},
		{
			name: "stacked (highest priority)",
			reason: DeletionReason{
				StackedCleanup: &StackedReason{StackThreshold: 98, StackAgeDays: 14, ActualPercent: 99, ActualAgeDays: 20},
				AgeThreshold:   &AgeReason{ConfiguredDays: 7, ActualAgeDays: 20},
				DiskThreshold:  &DiskReason{ConfiguredPercent: 90, ActualPercent: 99},
			},
			want: "stacked_cleanup",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.reason.GetPrimaryReason(); got != tt.want {
				t.Errorf("GetPrimaryReason() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestEvaluateDeletionReason(t *testing.T) {
	scanner := &Scanner{}

	tests := []struct {
		name          string
		rule          config.PathRule
		ageInDays     int
		diskUsage     float64
		expectStacked bool
		expectDisk    bool
		expectAge     bool
	}{
		{
			name: "age only trigger",
			rule: config.PathRule{
				Path:           "/var/log",
				AgeOffDays:     7,
				MaxFreePercent: 90,
				StackThreshold: 98,
				StackAgeDays:   14,
			},
			ageInDays:  10,
			diskUsage:  85,
			expectAge:  true,
			expectDisk: false,
		},
		{
			name: "disk only trigger",
			rule: config.PathRule{
				Path:           "/var/log",
				AgeOffDays:     7,
				MaxFreePercent: 90,
				StackThreshold: 98,
				StackAgeDays:   14,
			},
			ageInDays:  3,
			diskUsage:  92,
			expectDisk: true,
			expectAge:  false,
		},
		{
			name: "both age and disk (not stacked)",
			rule: config.PathRule{
				Path:           "/var/log",
				AgeOffDays:     7,
				MaxFreePercent: 90,
				StackThreshold: 98,
				StackAgeDays:   14,
			},
			ageInDays:  10,
			diskUsage:  92,
			expectAge:  true,
			expectDisk: true,
		},
		{
			name: "stacked cleanup (all three)",
			rule: config.PathRule{
				Path:           "/var/log",
				AgeOffDays:     7,
				MaxFreePercent: 90,
				StackThreshold: 98,
				StackAgeDays:   14,
			},
			ageInDays:     20,
			diskUsage:     99,
			expectStacked: true,
			expectDisk:    true,
			expectAge:     true,
		},
		{
			name: "no trigger",
			rule: config.PathRule{
				Path:           "/var/log",
				AgeOffDays:     7,
				MaxFreePercent: 90,
				StackThreshold: 98,
				StackAgeDays:   14,
			},
			ageInDays: 3,
			diskUsage: 85,
		},
		{
			name: "stacked threshold met but age not met",
			rule: config.PathRule{
				Path:           "/var/log",
				AgeOffDays:     7,
				MaxFreePercent: 90,
				StackThreshold: 98,
				StackAgeDays:   14,
			},
			ageInDays:  10,
			diskUsage:  99,
			expectDisk: true,
			expectAge:  true,
			// stacked NOT active because age < stack_age_days
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			reason := scanner.evaluateDeletionReason(&tt.rule, tt.ageInDays, tt.diskUsage, nil)

			if tt.expectStacked && reason.StackedCleanup == nil {
				t.Error("Expected StackedCleanup to be set")
			}
			if !tt.expectStacked && reason.StackedCleanup != nil {
				t.Error("Expected StackedCleanup to be nil")
			}

			if tt.expectDisk && reason.DiskThreshold == nil {
				t.Error("Expected DiskThreshold to be set")
			}
			if !tt.expectDisk && reason.DiskThreshold != nil {
				t.Error("Expected DiskThreshold to be nil")
			}

			if tt.expectAge && reason.AgeThreshold == nil {
				t.Error("Expected AgeThreshold to be set")
			}
			if !tt.expectAge && reason.AgeThreshold != nil {
				t.Error("Expected AgeThreshold to be nil")
			}

			// Verify HasReason logic
			if (tt.expectStacked || tt.expectDisk || tt.expectAge) && !reason.HasReason() {
				t.Error("Expected HasReason() to return true")
			}
			if !tt.expectStacked && !tt.expectDisk && !tt.expectAge && reason.HasReason() {
				t.Error("Expected HasReason() to return false")
			}
		})
	}
}
