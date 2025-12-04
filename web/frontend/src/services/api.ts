import apiClient from './apiClient';
import { DeletionsLogResponse, ReasonFilter, ActionFilter } from '../types/deletions';

export const getDeletionsLog = async (
  limit: number = 100,
  page: number = 1,
  action?: ActionFilter,
  reason?: ReasonFilter,
  path?: string
): Promise<DeletionsLogResponse> => {
  const params: Record<string, string | number> = {
    limit,
    page,
  };

  // Only add filter params if they're not 'all'
  if (action && action !== 'all') {
    params.action = action;
  }
  if (reason && reason !== 'all') {
    params.reason = reason;
  }
  if (path) {
    params.path = path;
  }

  const response = await apiClient.get<DeletionsLogResponse>(
    '/deletions/log',
    { params }
  );

  return response.data;
};

