export interface DeletionLogEntry {
  timestamp: string;
  action: string;
  path: string;
  file_name: string;
  object_type: string;
  size: number;
  deletion_reason: string;
  human_reason: string;
  primary_reason: string;
  path_rule: string;
  error_message?: string;
}

export interface DeletionsLogResponse {
  entries: DeletionLogEntry[];
  total_count: number;
  page_size: number;
  page: number;
  has_more?: boolean;
}

export type ReasonFilter = 'all' | 'age_threshold' | 'disk_threshold' | 'combined' | 'stacked_cleanup' | 'legacy';

export type ActionFilter = 'all' | 'DELETE' | 'SKIP' | 'ERROR' | 'DRY_RUN';

