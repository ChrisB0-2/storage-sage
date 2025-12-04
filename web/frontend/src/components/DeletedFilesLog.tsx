import React, { useState, useEffect } from 'react';

import { Link } from 'react-router-dom';
import {
  ArrowRightOnRectangleIcon,
  ChartBarIcon,
  Cog6ToothIcon,
  DocumentTextIcon,
} from '@heroicons/react/24/outline';

import { getDeletionsLog } from '../services/api';
import { DeletionLogEntry, ReasonFilter, ActionFilter } from '../types/deletions';

interface DeletedFilesLogProps {
  onLogout: () => void;
}

const DeletedFilesLog: React.FC<DeletedFilesLogProps> = ({ onLogout }) => {
  const [entries, setEntries] = useState<DeletionLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Pagination
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [totalCount, setTotalCount] = useState(0);
  const [hasMore, setHasMore] = useState(false);

  // Filters
  const [reasonFilter, setReasonFilter] = useState<ReasonFilter>('all');
  const [actionFilter, setActionFilter] = useState<ActionFilter>('all');
  const [searchTerm, setSearchTerm] = useState('');

  // Sorting (keep client-side for now, or move to server later)
  const [sortField, setSortField] = useState<keyof DeletionLogEntry | null>(null);
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc');

  // Fetch data - UPDATED to pass filters to API
  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);
        // Pass filters to API for server-side filtering
        const response = await getDeletionsLog(
          pageSize,
          page,
          actionFilter !== 'all' ? actionFilter : undefined,
          reasonFilter !== 'all' ? reasonFilter : undefined,
          searchTerm || undefined
        );
        setEntries(response.entries);
        setTotalCount(response.total_count);
        setHasMore(response.has_more || false);
        setError(null);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load deletion log');
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [page, pageSize, reasonFilter, actionFilter, searchTerm]);

  // Sort entries (keep client-side sorting)
  const sortedEntries = [...entries].sort((a, b) => {
    if (!sortField) return 0;

    let aVal: any = a[sortField];
    let bVal: any = b[sortField];

    // Handle different field types
    if (sortField === 'timestamp') {
      aVal = new Date(aVal).getTime();
      bVal = new Date(bVal).getTime();
    } else if (sortField === 'size') {
      aVal = Number(aVal);
      bVal = Number(bVal);
    } else {
      aVal = String(aVal).toLowerCase();
      bVal = String(bVal).toLowerCase();
    }

    if (aVal < bVal) return sortDirection === 'asc' ? -1 : 1;
    if (aVal > bVal) return sortDirection === 'asc' ? 1 : -1;
    return 0;
  });

  // Handle column sort
  const handleSort = (field: keyof DeletionLogEntry) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  // Format file size
  const formatSize = (bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
  };

  // Format timestamp
  const formatTimestamp = (timestamp: string): string => {
    const date = new Date(timestamp);
    return date.toLocaleString();
  };

  // Get badge color based on reason
  const getReasonBadgeColor = (primaryReason: string): string => {
    switch (primaryReason) {
      case 'age_threshold':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'disk_threshold':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
      case 'combined':
        return 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200';
      case 'stacked_cleanup':
        return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
      case 'legacy':
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
      default:
        return 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400';
    }
  };

  // Get action badge color
  const getActionBadgeColor = (action: string): string => {
    switch (action) {
      case 'DELETE':
        return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
      case 'SKIP':
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
      case 'ERROR':
        return 'bg-red-200 text-red-900 dark:bg-red-800 dark:text-red-100';
      case 'DRY_RUN':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
    }
  };

  // Sort indicator component
  const SortIndicator = ({ field }: { field: keyof DeletionLogEntry }) => {
    if (sortField !== field) return null;

    return (
      <span className="ml-1">
        {sortDirection === 'asc' ? '↑' : '↓'}
      </span>
    );
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-900">
        <div className="flex justify-center items-center h-64">
          <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900">
      {/* Navigation */}
      <nav className="bg-gray-800 border-b border-gray-700">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center">
              <h1 className="text-xl font-bold text-white">StorageSage</h1>
            </div>
            <div className="flex items-center space-x-4">
              <Link
                to="/dashboard"
                className="text-gray-300 hover:text-white px-3 py-2 rounded-md text-sm font-medium flex items-center"
              >
                <ChartBarIcon className="h-5 w-5 mr-2" />
                Dashboard
              </Link>
              <Link
                to="/config"
                className="text-gray-300 hover:text-white px-3 py-2 rounded-md text-sm font-medium flex items-center"
              >
                <Cog6ToothIcon className="h-5 w-5 mr-2" />
                Configuration
              </Link>
              <Link
                to="/deletions"
                className="text-white bg-blue-600 px-3 py-2 rounded-md text-sm font-medium flex items-center"
              >
                <DocumentTextIcon className="h-5 w-5 mr-2" />
                Deletion Log
              </Link>
              <button
                onClick={onLogout}
                className="text-gray-300 hover:text-white px-3 py-2 rounded-md text-sm font-medium flex items-center"
              >
                <ArrowRightOnRectangleIcon className="h-5 w-5 mr-2" />
                Logout
              </button>
            </div>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Header */}
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold text-white">Deleted Files Log</h2>
          <div className="text-sm text-gray-400">
            {totalCount} total entries
          </div>
        </div>

        {error && (
          <div className="bg-red-900 border border-red-700 rounded-lg p-4 mb-4">
            <p className="text-red-200">Error: {error}</p>
          </div>
        )}

        {/* Filters */}
        <div className="bg-gray-800 rounded-lg shadow border border-gray-700 p-4 mb-6 space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* Search */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-1">
                Search Path
              </label>
              <input
                type="text"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Filter by path..."
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            {/* Reason Filter */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-1">
                Deletion Reason
              </label>
              <select
                value={reasonFilter}
                onChange={(e) => setReasonFilter(e.target.value as ReasonFilter)}
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="all">All Reasons</option>
                <option value="age_threshold">Age Threshold</option>
                <option value="disk_threshold">Disk Threshold</option>
                <option value="combined">Combined</option>
                <option value="stacked_cleanup">Stacked Cleanup</option>
                <option value="legacy">Legacy</option>
              </select>
            </div>

            {/* Action Filter */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-1">
                Action
              </label>
              <select
                value={actionFilter}
                onChange={(e) => setActionFilter(e.target.value as ActionFilter)}
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="all">All Actions</option>
                <option value="DELETE">Deleted</option>
                <option value="SKIP">Skipped</option>
                <option value="ERROR">Error</option>
                <option value="DRY_RUN">Dry Run</option>
              </select>
            </div>
          </div>

          {/* Active filters count */}
          {(reasonFilter !== 'all' || actionFilter !== 'all' || searchTerm) && (
            <div className="text-sm text-gray-400">
              Showing {entries.length} of {totalCount} entries
              <button
                onClick={() => {
                  setReasonFilter('all');
                  setActionFilter('all');
                  setSearchTerm('');
                  setPage(1);
                }}
                className="ml-2 text-blue-400 hover:text-blue-300"
              >
                Clear filters
              </button>
            </div>
          )}
        </div>

        {/* Table */}
        <div className="bg-gray-800 rounded-lg shadow border border-gray-700 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-700">
              <thead className="bg-gray-700">
                <tr>
                  <th
                    className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer hover:bg-gray-700"
                    onClick={() => handleSort('timestamp')}
                  >
                    Timestamp <SortIndicator field="timestamp" />
                  </th>
                  <th
                    className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer hover:bg-gray-700"
                    onClick={() => handleSort('action')}
                  >
                    Action <SortIndicator field="action" />
                  </th>
                  <th
                    className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer hover:bg-gray-700"
                    onClick={() => handleSort('path')}
                  >
                    Path <SortIndicator field="path" />
                  </th>
                  <th
                    className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer hover:bg-gray-700"
                    onClick={() => handleSort('size')}
                  >
                    Size <SortIndicator field="size" />
                  </th>
                  <th
                    className="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider cursor-pointer hover:bg-gray-700"
                    onClick={() => handleSort('primary_reason')}
                  >
                    Deletion Reason <SortIndicator field="primary_reason" />
                  </th>
                </tr>
              </thead>
              <tbody className="bg-gray-800 divide-y divide-gray-700">
                {sortedEntries.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="px-6 py-4 text-center text-gray-400">
                      No entries found
                    </td>
                  </tr>
                ) : (
                  sortedEntries.map((entry, index) => (
                    <tr key={index} className="hover:bg-gray-700">
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-300">
                        {formatTimestamp(entry.timestamp)}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`px-2 py-1 text-xs font-medium rounded-full ${getActionBadgeColor(entry.action)}`}>
                          {entry.action}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-sm text-gray-300">
                        <div className="max-w-md truncate" title={entry.path}>
                          {entry.path}
                        </div>
                        <div className="text-xs text-gray-500">
                          {entry.object_type}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-300">
                        {formatSize(entry.size)}
                      </td>
                      <td className="px-6 py-4">
                        <div className="flex flex-col space-y-1">
                          <span className={`inline-flex px-2 py-1 text-xs font-medium rounded-full ${getReasonBadgeColor(entry.primary_reason)}`}>
                            {entry.primary_reason.replace('_', ' ')}
                          </span>
                          <span className="text-xs text-gray-400" title={entry.deletion_reason}>
                            {entry.human_reason}
                          </span>
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Pagination */}
        <div className="flex items-center justify-between bg-gray-800 px-4 py-3 rounded-lg shadow border border-gray-700 mt-6">
          <div className="flex items-center space-x-2">
            <label className="text-sm text-gray-300">Rows per page:</label>
            <select
              value={pageSize}
              onChange={(e) => {
                setPageSize(Number(e.target.value));
                setPage(1);
              }}
              className="bg-gray-700 border border-gray-600 rounded px-2 py-1 text-sm text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value={10}>10</option>
              <option value={25}>25</option>
              <option value={50}>50</option>
              <option value={100}>100</option>
            </select>
          </div>

          <div className="flex items-center space-x-2">
            <button
              onClick={() => setPage(page - 1)}
              disabled={page === 1}
              className="px-3 py-1 border border-gray-600 rounded text-sm text-gray-300 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-700 disabled:hover:bg-transparent"
            >
              Previous
            </button>
            <span className="text-sm text-gray-300">
              Page {page}
            </span>
            <button
              onClick={() => setPage(page + 1)}
              disabled={!hasMore}
              className="px-3 py-1 border border-gray-600 rounded text-sm text-gray-300 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-700 disabled:hover:bg-transparent"
            >
              Next
            </button>
          </div>
        </div>
      </main>
    </div>
  );
};

export default DeletedFilesLog;

