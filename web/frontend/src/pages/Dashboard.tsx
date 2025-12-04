import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import {
  ArrowPathIcon,
  ChartBarIcon,
  Cog6ToothIcon,
  ArrowRightOnRectangleIcon,
  DocumentTextIcon,
} from '@heroicons/react/24/outline';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import toast from 'react-hot-toast';
import apiClient from '../services/apiClient';

interface DashboardProps {
  onLogout: () => void;
}

interface Metrics {
  files_deleted: number;
  bytes_freed: number;
  errors: number;
  cleanup_running: boolean;
  cleanup_count: number;
  avg_duration: number;
}

export default function Dashboard({ onLogout }: DashboardProps) {
  const [metrics, setMetrics] = useState<Metrics>({
    files_deleted: 0,
    bytes_freed: 0,
    errors: 0,
    cleanup_running: false,
    cleanup_count: 0,
    avg_duration: 0,
  });
  const [isTriggering, setIsTriggering] = useState(false);
  const [historyData, setHistoryData] = useState<any[]>([]);

  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const response = await apiClient.get('/metrics/current');
        const text = response.data;
        
        // Parse Prometheus format
        const filesMatch = text.match(/storagesage_files_deleted_total\s+([\d.e+]+)/);
        const bytesMatch = text.match(/storagesage_bytes_freed_total\s+([\d.e+]+)/);
        const errorsMatch = text.match(/storagesage_errors_total\s+([\d.e+]+)/);
        const cleanupCountMatch = text.match(/storagesage_cleanup_duration_seconds_count\s+([\d.e+]+)/);
        const cleanupSumMatch = text.match(/storagesage_cleanup_duration_seconds_sum\s+([\d.e+]+)/);
        
        const filesDeleted = filesMatch ? parseFloat(filesMatch[1]) : 0;
        const bytesFreed = bytesMatch ? parseFloat(bytesMatch[1]) : 0;
        const errors = errorsMatch ? parseFloat(errorsMatch[1]) : 0;
        const cleanupCount = cleanupCountMatch ? parseFloat(cleanupCountMatch[1]) : 0;
        const cleanupSum = cleanupSumMatch ? parseFloat(cleanupSumMatch[1]) : 0;
        const avgDuration = cleanupCount > 0 ? cleanupSum / cleanupCount : 0;

        setMetrics({
          files_deleted: filesDeleted,
          bytes_freed: bytesFreed,
          errors: errors,
          cleanup_running: false,
          cleanup_count: cleanupCount,
          avg_duration: avgDuration,
        });

        // Add to history for chart
        setHistoryData((prev) => {
          const newData = [
            ...prev.slice(-19), // Keep last 19 points
            {
              time: new Date().toLocaleTimeString(),
              filesDeleted: filesDeleted,
              bytesFreed: Math.round(bytesFreed / 1024 / 1024), // Convert to MB
            },
          ];
          return newData;
        });
      } catch (error) {
        // Only log errors in development
        if (import.meta.env.DEV) {
          console.error('Failed to fetch metrics:', error);
        }
        // Silently fail - metrics will retry on next poll
      }
    };

    // Fetch immediately
    fetchMetrics();
    
    // Poll every 5 seconds
    const interval = setInterval(fetchMetrics, 5000);
    
    return () => clearInterval(interval);
  }, []);

  const handleTriggerCleanup = async () => {
    setIsTriggering(true);
    try {
      await apiClient.post('/cleanup/trigger');
      toast.success('Cleanup triggered successfully');
    } catch (error: any) {
      const msg =
        error.response?.data?.message ||
        error.message ||
        'Failed to trigger cleanup';
      toast.error(msg);
    } finally {
      setIsTriggering(false);
    }
  };

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
  };

  return (
    <div className="min-h-screen bg-gray-900">
      {/* Navigation */}
      <nav className="bg-gray-800 border-b border-gray-700">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center">
              <h1 className="text-xl font-bold text-white">StorageSage</h1>
              <span className="ml-3 px-2 py-1 text-xs bg-yellow-600 text-white rounded">DRY-RUN MODE</span>
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
                className="text-gray-300 hover:text-white px-3 py-2 rounded-md text-sm font-medium flex items-center"
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
        {/* Stats Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-400 text-sm">Files Deleted</p>
                <p className="text-3xl font-bold text-white mt-2">{metrics.files_deleted.toLocaleString()}</p>
              </div>
              <div className="bg-blue-600 rounded-full p-3">
                <svg className="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </div>
            </div>
          </div>

          <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-400 text-sm">Space Freed</p>
                <p className="text-3xl font-bold text-white mt-2">{formatBytes(metrics.bytes_freed)}</p>
              </div>
              <div className="bg-green-600 rounded-full p-3">
                <svg className="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
                </svg>
              </div>
            </div>
          </div>

          <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-400 text-sm">Cleanup Cycles</p>
                <p className="text-3xl font-bold text-white mt-2">{metrics.cleanup_count}</p>
                <p className="text-xs text-gray-500 mt-1">Avg: {metrics.avg_duration.toFixed(3)}s</p>
              </div>
              <div className="bg-purple-600 rounded-full p-3">
                <svg className="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
              </div>
            </div>
          </div>

          <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-400 text-sm">Errors</p>
                <p className="text-3xl font-bold text-white mt-2">{metrics.errors}</p>
              </div>
              <div className={`rounded-full p-3 ${metrics.errors > 0 ? 'bg-red-600' : 'bg-gray-600'}`}>
                <svg className="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
            </div>
            <button
              onClick={handleTriggerCleanup}
              disabled={isTriggering}
              className="mt-4 w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 text-white text-sm py-2 px-4 rounded-md transition-colors flex items-center justify-center"
            >
              <ArrowPathIcon className={`h-4 w-4 mr-2 ${isTriggering ? 'animate-spin' : ''}`} />
              {isTriggering ? 'Triggering...' : 'Manual Cleanup'}
            </button>
          </div>
        </div>

        {/* Chart */}
        <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
          <h2 className="text-xl font-bold text-white mb-4">Cleanup Activity</h2>
          {historyData.length > 0 ? (
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={historyData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                <XAxis dataKey="time" stroke="#9CA3AF" />
                <YAxis stroke="#9CA3AF" />
                <Tooltip
                  contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151' }}
                  labelStyle={{ color: '#F3F4F6' }}
                />
                <Legend />
                <Line type="monotone" dataKey="filesDeleted" stroke="#3B82F6" name="Files Deleted" />
                <Line type="monotone" dataKey="bytesFreed" stroke="#10B981" name="Space Freed (MB)" />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <div className="text-center text-gray-400 py-12">
              Collecting metrics data...
            </div>
          )}
        </div>

        {/* Info Banner */}
        <div className="mt-6 bg-yellow-900 border border-yellow-700 rounded-lg p-4">
          <p className="text-yellow-200 text-sm">
            <strong>Note:</strong> The daemon is running in <strong>DRY-RUN</strong> mode. Files are identified but not actually deleted. 
            To enable real deletion, restart the service without the --dry-run flag.
          </p>
        </div>
      </main>
    </div>
  );
}
