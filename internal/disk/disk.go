package disk

import (
	"os"
	"syscall"
	"time"
)

// GetDiskUsage returns the percentage of disk space used for a given path
func GetDiskUsage(path string) (usedPercent float64, freeBytes int64, totalBytes int64, err error) {
	var stat syscall.Statfs_t
	err = syscall.Statfs(path, &stat)
	if err != nil {
		return 0, 0, 0, err
	}

	// Calculate total and free bytes
	totalBytes = int64(stat.Blocks) * int64(stat.Bsize)
	freeBytes = int64(stat.Bavail) * int64(stat.Bsize)
	usedBytes := totalBytes - freeBytes

	// Calculate percentage used
	if totalBytes > 0 {
		usedPercent = (float64(usedBytes) / float64(totalBytes)) * 100.0
	}

	return usedPercent, freeBytes, totalBytes, nil
}

// GetFreePercent returns the percentage of free disk space
func GetFreePercent(path string) (float64, error) {
	usedPercent, _, _, err := GetDiskUsage(path)
	if err != nil {
		return 0, err
	}
	return 100.0 - usedPercent, nil
}

// IsNFSStale checks if a path is on a stale NFS mount by attempting a quick stat
// with timeout. Returns true if the operation times out or fails with NFS-specific errors.
func IsNFSStale(path string, timeout time.Duration) bool {
	done := make(chan bool, 1)
	var err error

	go func() {
		_, err = os.Stat(path)
		done <- true
	}()

	select {
	case <-done:
		// Check for NFS-specific errors
		if err != nil {
			// Common NFS errors: EIO, ESTALE, ENXIO
			if os.IsTimeout(err) ||
				err == syscall.EIO ||
				err == syscall.ESTALE ||
				err == syscall.ENXIO {
				return true
			}
		}
		return false
	case <-time.After(timeout):
		// Operation timed out - likely stale NFS
		return true
	}
}

