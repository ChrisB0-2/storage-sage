import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import {
  ChartBarIcon,
  Cog6ToothIcon,
  ArrowRightOnRectangleIcon,
  CheckCircleIcon,
  XCircleIcon,
  PlusIcon,
  TrashIcon,
  DocumentTextIcon,
} from '@heroicons/react/24/outline';
import toast from 'react-hot-toast';
import apiClient from '../services/apiClient';

interface ConfigEditorProps {
  onLogout: () => void;
}

interface PathRule {
  path: string;
  age_off_days?: number;
  min_free_percent?: number;
  max_free_percent?: number;
  target_free_percent?: number;
  priority?: number;
  stack_threshold?: number;
  stack_age_days?: number;
}

interface Config {
  scan_paths?: string[];
  age_off_days?: number;
  min_free_percent?: number;
  interval_minutes?: number;
  paths?: PathRule[];
  prometheus?: {
    port: number;
  };
  logging?: {
    rotation_days?: number;
  };
  resource_limits?: {
    max_cpu_percent?: number;
  };
  cleanup_options?: {
    recursive?: boolean;
    delete_dirs?: boolean;
  };
  nfs_timeout_seconds?: number;
}

export default function ConfigEditor({ onLogout }: ConfigEditorProps) {
  const [config, setConfig] = useState<Config>({
    scan_paths: [],
    age_off_days: 7,
    min_free_percent: 10,
    interval_minutes: 15,
    paths: [],
    prometheus: {
      port: 9090,
    },
    logging: {
      rotation_days: 30,
    },
    resource_limits: {
      max_cpu_percent: 10.0,
    },
    cleanup_options: {
      recursive: true,
      delete_dirs: false,
    },
    nfs_timeout_seconds: 5,
  });
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isValid, setIsValid] = useState<boolean | null>(null);
  const [newPath, setNewPath] = useState('');
  const [showAdvanced, setShowAdvanced] = useState(true);

  useEffect(() => {
    fetchConfig();
  }, []);

  const fetchConfig = async () => {
    setIsLoading(true);
    try {
      const response = await apiClient.get<Config>('/config');
      setConfig(response.data);
      setIsValid(true);
    } catch (error: any) {
      const msg =
        error.response?.data?.message ||
        error.message ||
        'Failed to load configuration';
      toast.error(msg);
    } finally {
      setIsLoading(false);
    }
  };

  const validateConfig = async () => {
    try {
      await apiClient.post('/config/validate', config);
      setIsValid(true);
      toast.success('Configuration is valid');
    } catch (error: any) {
      setIsValid(false);
      const msg =
        error.response?.data?.message ||
        error.message ||
        'Configuration validation failed';
      toast.error(msg);
    }
  };

  const saveConfig = async () => {
    setIsSaving(true);
    try {
      await apiClient.put('/config', config);
      toast.success('Configuration saved successfully');
      setIsValid(true);
    } catch (error: any) {
      const msg =
        error.response?.data?.message ||
        error.message ||
        'Failed to save configuration';
      toast.error(msg);
    } finally {
      setIsSaving(false);
    }
  };

  const addPath = () => {
    if (newPath && !config.paths?.some(p => p.path === newPath)) {
      setConfig({
        ...config,
        paths: [
          ...(config.paths || []),
          {
            path: newPath,
            age_off_days: config.age_off_days || 7,
            min_free_percent: config.min_free_percent || 10,
            max_free_percent: 90,
            target_free_percent: 80,
            priority: (config.paths?.length || 0) + 1,
            stack_threshold: 98,
            stack_age_days: 14,
          },
        ],
      });
      setNewPath('');
      setIsValid(null);
    }
  };

  const removePath = (index: number) => {
    const newPaths = [...(config.paths || [])];
    newPaths.splice(index, 1);
    setConfig({ ...config, paths: newPaths });
    setIsValid(null);
  };

  const updatePathRule = (index: number, field: keyof PathRule, value: any) => {
    const newPaths = [...(config.paths || [])];
    newPaths[index] = { ...newPaths[index], [field]: value };
    setConfig({ ...config, paths: newPaths });
    setIsValid(null);
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-900 flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
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
                className="text-white px-3 py-2 rounded-md text-sm font-medium flex items-center bg-gray-700"
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
      <main className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
          <div className="px-6 py-4 border-b border-gray-700 flex items-center justify-between">
            <h2 className="text-2xl font-bold text-white">Configuration</h2>
            {isValid !== null && (
              <div className="flex items-center">
                {isValid ? (
                  <>
                    <CheckCircleIcon className="h-6 w-6 text-green-500 mr-2" />
                    <span className="text-green-500 text-sm">Valid</span>
                  </>
                ) : (
                  <>
                    <XCircleIcon className="h-6 w-6 text-red-500 mr-2" />
                    <span className="text-red-500 text-sm">Invalid</span>
                  </>
                )}
              </div>
            )}
          </div>

          <div className="p-6 space-y-6">
            {/* Global Settings */}
            <div className="border-b border-gray-700 pb-6">
              <h3 className="text-lg font-semibold text-white mb-4">Global Settings</h3>
              
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {/* Age Off Days */}
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">
                    Age Off Days (Default)
                  </label>
                  <input
                    type="number"
                    value={config.age_off_days || 7}
                    onChange={(e) => {
                      setConfig({ ...config, age_off_days: parseInt(e.target.value) });
                      setIsValid(null);
                    }}
                    className="w-full bg-gray-700 border border-gray-600 rounded-md px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-sm text-gray-400 mt-1">
                    Default age threshold for file deletion
                  </p>
                </div>

                {/* Min Free Percent */}
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">
                    Minimum Free Percent (Default)
                  </label>
                  <input
                    type="number"
                    value={config.min_free_percent || 10}
                    onChange={(e) => {
                      setConfig({ ...config, min_free_percent: parseInt(e.target.value) });
                      setIsValid(null);
                    }}
                    className="w-full bg-gray-700 border border-gray-600 rounded-md px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-sm text-gray-400 mt-1">
                    Default minimum free space percentage
                  </p>
                </div>

                {/* Interval */}
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">
                    Cleanup Interval (minutes)
                  </label>
                  <input
                    type="number"
                    value={config.interval_minutes || 15}
                    onChange={(e) => {
                      setConfig({ ...config, interval_minutes: parseInt(e.target.value) });
                      setIsValid(null);
                    }}
                    className="w-full bg-gray-700 border border-gray-600 rounded-md px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-sm text-gray-400 mt-1">
                    How often to run cleanup cycles
                  </p>
                </div>

                {/* Prometheus Port */}
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">
                    Prometheus Metrics Port
                  </label>
                  <input
                    type="number"
                    value={config.prometheus?.port || 9090}
                    onChange={(e) => {
                      setConfig({
                        ...config,
                        prometheus: { port: parseInt(e.target.value) },
                      });
                      setIsValid(null);
                    }}
                    className="w-full bg-gray-700 border border-gray-600 rounded-md px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>
            </div>

            {/* Advanced Path Rules */}
            <div className="border-b border-gray-700 pb-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-white">Advanced Path Rules</h3>
                <button
                  onClick={() => setShowAdvanced(!showAdvanced)}
                  className="text-sm text-blue-400 hover:text-blue-300"
                >
                  {showAdvanced ? 'Hide' : 'Show'} Advanced
                </button>
              </div>

              {/* Add New Path */}
              <div className="flex mb-4">
                <input
                  type="text"
                  value={newPath}
                  onChange={(e) => setNewPath(e.target.value)}
                  placeholder="/path/to/directory"
                  className="flex-1 bg-gray-700 border border-gray-600 rounded-l-md px-4 py-2 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  onKeyPress={(e) => e.key === 'Enter' && addPath()}
                />
                <button
                  onClick={addPath}
                  className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-r-md flex items-center"
                >
                  <PlusIcon className="h-5 w-5 mr-1" />
                  Add Path
                </button>
              </div>

              {/* Path Rules List */}
              <div className="space-y-4">
                {config.paths?.map((pathRule, index) => (
                  <div key={index} className="bg-gray-700 rounded-lg p-4 border border-gray-600">
                    <div className="flex items-center justify-between mb-4">
                      <div className="flex-1">
                        <input
                          type="text"
                          value={pathRule.path}
                          onChange={(e) => updatePathRule(index, 'path', e.target.value)}
                          className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white font-medium focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                      </div>
                      <button
                        onClick={() => removePath(index)}
                        className="ml-2 text-red-500 hover:text-red-400 p-2"
                      >
                        <TrashIcon className="h-5 w-5" />
                      </button>
                    </div>

                    {showAdvanced && (
                      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-4">
                        <div>
                          <label className="block text-xs font-medium text-gray-400 mb-1">
                            Age Off Days
                          </label>
                          <input
                            type="number"
                            value={pathRule.age_off_days || ''}
                            onChange={(e) => updatePathRule(index, 'age_off_days', parseInt(e.target.value))}
                            className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-400 mb-1">
                            Priority (lower = higher)
                          </label>
                          <input
                            type="number"
                            value={pathRule.priority || ''}
                            onChange={(e) => updatePathRule(index, 'priority', parseInt(e.target.value))}
                            className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-400 mb-1">
                            Min Free %
                          </label>
                          <input
                            type="number"
                            value={pathRule.min_free_percent || ''}
                            onChange={(e) => updatePathRule(index, 'min_free_percent', parseInt(e.target.value))}
                            className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-400 mb-1">
                            Max Free % (trigger)
                          </label>
                          <input
                            type="number"
                            value={pathRule.max_free_percent || ''}
                            onChange={(e) => updatePathRule(index, 'max_free_percent', parseInt(e.target.value))}
                            className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-400 mb-1">
                            Target Free % (after cleanup)
                          </label>
                          <input
                            type="number"
                            value={pathRule.target_free_percent || ''}
                            onChange={(e) => updatePathRule(index, 'target_free_percent', parseInt(e.target.value))}
                            className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-400 mb-1">
                            Stack Threshold %
                          </label>
                          <input
                            type="number"
                            value={pathRule.stack_threshold || ''}
                            onChange={(e) => updatePathRule(index, 'stack_threshold', parseInt(e.target.value))}
                            className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          />
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-400 mb-1">
                            Stack Age Days
                          </label>
                          <input
                            type="number"
                            value={pathRule.stack_age_days || ''}
                            onChange={(e) => updatePathRule(index, 'stack_age_days', parseInt(e.target.value))}
                            className="w-full bg-gray-600 border border-gray-500 rounded-md px-3 py-2 text-white text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          />
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>

            {/* Resource Limits */}
            <div className="border-b border-gray-700 pb-6">
              <h3 className="text-lg font-semibold text-white mb-4">Resource Limits</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-2">
                    Max CPU Percent
                  </label>
                  <input
                    type="number"
                    step="0.1"
                    value={config.resource_limits?.max_cpu_percent || 10.0}
                    onChange={(e) => {
                      setConfig({
                        ...config,
                        resource_limits: {
                          max_cpu_percent: parseFloat(e.target.value),
                        },
                      });
                      setIsValid(null);
                    }}
                    className="w-full bg-gray-700 border border-gray-600 rounded-md px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <p className="text-sm text-gray-400 mt-1">
                    Maximum CPU usage percentage (e.g., 10.0)
                  </p>
                </div>
              </div>
            </div>

            {/* Cleanup Options */}
            <div className="border-b border-gray-700 pb-6">
              <h3 className="text-lg font-semibold text-white mb-4">Cleanup Options</h3>
              <div className="space-y-4">
                <div className="flex items-center">
                  <input
                    type="checkbox"
                    id="recursive"
                    checked={config.cleanup_options?.recursive ?? true}
                    onChange={(e) => {
                      setConfig({
                        ...config,
                        cleanup_options: {
                          ...config.cleanup_options,
                          recursive: e.target.checked,
                        },
                      });
                      setIsValid(null);
                    }}
                    className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                  />
                  <label htmlFor="recursive" className="ml-2 text-sm text-gray-300">
                    Enable recursive deletion
                  </label>
                </div>
                <div className="flex items-center">
                  <input
                    type="checkbox"
                    id="delete_dirs"
                    checked={config.cleanup_options?.delete_dirs ?? false}
                    onChange={(e) => {
                      setConfig({
                        ...config,
                        cleanup_options: {
                          ...config.cleanup_options,
                          delete_dirs: e.target.checked,
                        },
                      });
                      setIsValid(null);
                    }}
                    className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                  />
                  <label htmlFor="delete_dirs" className="ml-2 text-sm text-gray-300">
                    Allow directory deletion (use with caution)
                  </label>
                </div>
              </div>
            </div>

            {/* Logging & NFS */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-2">
                  Log Rotation Days
                </label>
                <input
                  type="number"
                  value={config.logging?.rotation_days || 30}
                  onChange={(e) => {
                    setConfig({
                      ...config,
                      logging: {
                        rotation_days: parseInt(e.target.value),
                      },
                    });
                    setIsValid(null);
                  }}
                  className="w-full bg-gray-700 border border-gray-600 rounded-md px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <p className="text-sm text-gray-400 mt-1">
                  Days to keep logs before rotation
                </p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-2">
                  NFS Timeout (seconds)
                </label>
                <input
                  type="number"
                  value={config.nfs_timeout_seconds || 5}
                  onChange={(e) => {
                    setConfig({
                      ...config,
                      nfs_timeout_seconds: parseInt(e.target.value),
                    });
                    setIsValid(null);
                  }}
                  className="w-full bg-gray-700 border border-gray-600 rounded-md px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <p className="text-sm text-gray-400 mt-1">
                  Timeout for NFS operations to prevent hangs
                </p>
              </div>
            </div>
          </div>

          {/* Actions */}
          <div className="px-6 py-4 bg-gray-750 border-t border-gray-700 flex justify-end space-x-4">
            <button
              onClick={validateConfig}
              className="px-4 py-2 border border-gray-600 text-gray-300 rounded-md hover:bg-gray-700 transition-colors"
            >
              Validate
            </button>
            <button
              onClick={saveConfig}
              disabled={isSaving || isValid === false}
              className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed transition-colors"
            >
              {isSaving ? 'Saving...' : 'Save Configuration'}
            </button>
          </div>
        </div>

        {/* Info */}
        <div className="mt-6 bg-blue-900 border border-blue-700 rounded-lg p-4">
          <p className="text-blue-200 text-sm">
            <strong>Info:</strong> Configuration changes will be automatically applied to the daemon. The daemon will reload the configuration without requiring a manual restart.
          </p>
        </div>
      </main>
    </div>
  );
}