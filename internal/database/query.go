package database

import (
	"database/sql"
	"time"
)

// GetRecentDeletions returns the N most recent deletion events
func (d *DeletionDB) GetRecentDeletions(limit int) ([]DeletionRecord, error) {
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	ORDER BY timestamp DESC
	LIMIT ?
	`

	return d.queryDeletions(query, limit)
}

// GetDeletionsByDateRange returns deletions within a time range
func (d *DeletionDB) GetDeletionsByDateRange(start, end time.Time) ([]DeletionRecord, error) {
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE timestamp BETWEEN ? AND ?
	ORDER BY timestamp DESC
	`

	return d.queryDeletions(query, start, end)
}

// GetDeletionsByReason returns deletions filtered by primary reason
func (d *DeletionDB) GetDeletionsByReason(primaryReason string) ([]DeletionRecord, error) {
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE primary_reason = ?
	ORDER BY timestamp DESC
	`

	return d.queryDeletions(query, primaryReason)
}

// GetDeletionsByPath returns deletions matching a path pattern
func (d *DeletionDB) GetDeletionsByPath(pathPattern string) ([]DeletionRecord, error) {
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE path LIKE ?
	ORDER BY timestamp DESC
	`

	return d.queryDeletions(query, pathPattern)
}

// GetDeletionsByAction returns deletions filtered by action type
func (d *DeletionDB) GetDeletionsByAction(action string) ([]DeletionRecord, error) {
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE action = ?
	ORDER BY timestamp DESC
	`

	return d.queryDeletions(query, action)
}

// GetLargestDeletions returns the N largest deletions by size
func (d *DeletionDB) GetLargestDeletions(limit int) ([]DeletionRecord, error) {
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE action = 'DELETE'
	ORDER BY size DESC
	LIMIT ?
	`

	return d.queryDeletions(query, limit)
}

// GetTotalSpaceFreed returns total bytes freed in a time range
func (d *DeletionDB) GetTotalSpaceFreed(start, end time.Time) (int64, error) {
	query := `
	SELECT COALESCE(SUM(size), 0)
	FROM deletions
	WHERE action = 'DELETE' AND timestamp BETWEEN ? AND ?
	`

	var total int64
	err := d.db.QueryRow(query, start, end).Scan(&total)
	return total, err
}

// GetDeletionCountByReason returns count of deletions grouped by reason
func (d *DeletionDB) GetDeletionCountByReason() (map[string]int, error) {
	query := `
	SELECT primary_reason, COUNT(*)
	FROM deletions
	WHERE action = 'DELETE'
	GROUP BY primary_reason
	`

	rows, err := d.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	counts := make(map[string]int)
	for rows.Next() {
		var reason string
		var count int
		if err := rows.Scan(&reason, &count); err != nil {
			return nil, err
		}
		counts[reason] = count
	}

	return counts, rows.Err()
}

// GetDeletionCountByAction returns count of operations grouped by action
func (d *DeletionDB) GetDeletionCountByAction() (map[string]int, error) {
	query := `
	SELECT action, COUNT(*)
	FROM deletions
	GROUP BY action
	`

	rows, err := d.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	counts := make(map[string]int)
	for rows.Next() {
		var action string
		var count int
		if err := rows.Scan(&action, &count); err != nil {
			return nil, err
		}
		counts[action] = count
	}

	return counts, rows.Err()
}

// DeletionStats holds aggregated statistics
type DeletionStats struct {
	TotalDeletions  int
	TotalSkipped    int
	TotalErrors     int
	TotalSpaceFreed int64
	ByReason        map[string]int
	ByAction        map[string]int
	StartDate       time.Time
	EndDate         time.Time
}

// GetDeletionStats returns comprehensive statistics for a time period
func (d *DeletionDB) GetDeletionStats(days int) (*DeletionStats, error) {
	since := time.Now().AddDate(0, 0, -days)
	now := time.Now()

	stats := &DeletionStats{
		StartDate: since,
		EndDate:   now,
	}

	// Total by action
	err := d.db.QueryRow(`
		SELECT 
			COUNT(CASE WHEN action = 'DELETE' THEN 1 END),
			COUNT(CASE WHEN action = 'SKIP' THEN 1 END),
			COUNT(CASE WHEN action = 'ERROR' THEN 1 END)
		FROM deletions 
		WHERE timestamp >= ?
	`, since).Scan(&stats.TotalDeletions, &stats.TotalSkipped, &stats.TotalErrors)
	if err != nil {
		return nil, err
	}

	// Total space freed
	stats.TotalSpaceFreed, err = d.GetTotalSpaceFreed(since, now)
	if err != nil {
		return nil, err
	}

	// Count by reason
	stats.ByReason, err = d.GetDeletionCountByReason()
	if err != nil {
		return nil, err
	}

	// Count by action
	stats.ByAction, err = d.GetDeletionCountByAction()
	if err != nil {
		return nil, err
	}

	return stats, nil
}

// GetTopPathsByDeletionCount returns paths with most deletions
func (d *DeletionDB) GetTopPathsByDeletionCount(limit int) (map[string]int, error) {
	query := `
	SELECT path, COUNT(*) as count
	FROM deletions
	WHERE action = 'DELETE'
	GROUP BY path
	ORDER BY count DESC
	LIMIT ?
	`

	rows, err := d.db.Query(query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	counts := make(map[string]int)
	for rows.Next() {
		var path string
		var count int
		if err := rows.Scan(&path, &count); err != nil {
			return nil, err
		}
		counts[path] = count
	}

	return counts, rows.Err()
}

// DeleteOldRecords removes records older than specified days (for cleanup)
func (d *DeletionDB) DeleteOldRecords(olderThanDays int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -olderThanDays)

	result, err := d.db.Exec(`
		DELETE FROM deletions WHERE timestamp < ?
	`, cutoff)
	if err != nil {
		return 0, err
	}

	return result.RowsAffected()
}

// queryDeletions is a helper function to execute queries and scan results
func (d *DeletionDB) queryDeletions(query string, args ...interface{}) ([]DeletionRecord, error) {
	rows, err := d.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var records []DeletionRecord
	for rows.Next() {
		var r DeletionRecord
		var errMsg sql.NullString

		err := rows.Scan(
			&r.ID, &r.Timestamp, &r.Action, &r.Path, &r.FileName,
			&r.ObjectType, &r.Size, &r.DeletionReason,
			&r.PrimaryReason, &r.PathRule, &errMsg,
		)
		if err != nil {
			return nil, err
		}

		if errMsg.Valid {
			r.ErrorMessage = errMsg.String
		}

		records = append(records, r)
	}

	return records, rows.Err()
}

// GetRecentDeletionsPaginated returns paginated recent deletions with total count
func (d *DeletionDB) GetRecentDeletionsPaginated(limit, offset int) ([]DeletionRecord, int, error) {
	// Get total count
	var totalCount int
	err := d.db.QueryRow("SELECT COUNT(*) FROM deletions").Scan(&totalCount)
	if err != nil {
		return nil, 0, err
	}

	// Get paginated records
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	ORDER BY timestamp DESC
	LIMIT ? OFFSET ?
	`

	records, err := d.queryDeletions(query, limit, offset)
	return records, totalCount, err
}

// GetDeletionsByActionPaginated returns paginated deletions by action
func (d *DeletionDB) GetDeletionsByActionPaginated(action string, limit, offset int) ([]DeletionRecord, int, error) {
	// Get total count
	var totalCount int
	err := d.db.QueryRow("SELECT COUNT(*) FROM deletions WHERE action = ?", action).Scan(&totalCount)
	if err != nil {
		return nil, 0, err
	}

	// Get paginated records
	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE action = ?
	ORDER BY timestamp DESC
	LIMIT ? OFFSET ?
	`

	records, err := d.queryDeletions(query, action, limit, offset)
	return records, totalCount, err
}

// GetDeletionsByReasonPaginated returns paginated deletions by reason
func (d *DeletionDB) GetDeletionsByReasonPaginated(reason string, limit, offset int) ([]DeletionRecord, int, error) {
	// Get total count
	var totalCount int
	err := d.db.QueryRow("SELECT COUNT(*) FROM deletions WHERE primary_reason = ?", reason).Scan(&totalCount)
	if err != nil {
		return nil, 0, err
	}

	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE primary_reason = ?
	ORDER BY timestamp DESC
	LIMIT ? OFFSET ?
	`

	records, err := d.queryDeletions(query, reason, limit, offset)
	return records, totalCount, err
}

// GetDeletionsByPathPaginated returns paginated deletions by path pattern
func (d *DeletionDB) GetDeletionsByPathPaginated(pathPattern string, limit, offset int) ([]DeletionRecord, int, error) {
	// Get total count
	var totalCount int
	err := d.db.QueryRow("SELECT COUNT(*) FROM deletions WHERE path LIKE ?", pathPattern).Scan(&totalCount)
	if err != nil {
		return nil, 0, err
	}

	query := `
	SELECT id, timestamp, action, path, file_name, object_type, size,
	       deletion_reason, primary_reason, path_rule, error_message
	FROM deletions
	WHERE path LIKE ?
	ORDER BY timestamp DESC
	LIMIT ? OFFSET ?
	`

	records, err := d.queryDeletions(query, pathPattern, limit, offset)
	return records, totalCount, err
}
