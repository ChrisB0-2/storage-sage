package limiter

import (
	"runtime"
	"time"
)

// CPULimiter throttles CPU usage to a maximum percentage
type CPULimiter struct {
	maxPercent float64
	lastSleep  time.Time
}

// NewCPULimiter creates a new CPU limiter
func NewCPULimiter(maxPercent float64) *CPULimiter {
	return &CPULimiter{
		maxPercent: maxPercent,
		lastSleep:  time.Now(),
	}
}

// Throttle sleeps to limit CPU usage to maxPercent
// This is a simple implementation that sleeps periodically
// For more accurate control, consider using cgroups or systemd limits
func (l *CPULimiter) Throttle() {
	if l.maxPercent <= 0 || l.maxPercent >= 100 {
		return // No limit or invalid
	}

	// Simple throttling: sleep for a percentage of time
	// If we want to use maxPercent CPU, we sleep for (100 - maxPercent) of the time
	sleepPercent := 100.0 - l.maxPercent

	// Calculate sleep duration based on a work cycle
	// This is a simplified approach - in practice, you'd want more sophisticated
	// CPU measurement and throttling
	workTime := 10 * time.Millisecond // Work for 10ms
	sleepTime := time.Duration(float64(workTime) * (sleepPercent / l.maxPercent))

	// Only sleep if enough time has passed since last sleep
	if time.Since(l.lastSleep) > workTime {
		time.Sleep(sleepTime)
		l.lastSleep = time.Now()
	}

	// Yield to other goroutines
	runtime.Gosched()
}

// SetMaxPercent updates the maximum CPU percentage
func (l *CPULimiter) SetMaxPercent(maxPercent float64) {
	l.maxPercent = maxPercent
}
