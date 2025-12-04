/**
 * Environment Configuration
 * Centralized configuration for environment variables with validation
 */

interface EnvConfig {
  apiUrl: string;
  apiTimeout: number;
  appEnv: string;
  isDevelopment: boolean;
  isProduction: boolean;
}

/**
 * Validates and returns environment configuration
 * Throws error if required variables are missing
 */
function getEnvConfig(): EnvConfig {
  const apiUrl = import.meta.env.VITE_API_URL;
  const apiTimeout = parseInt(import.meta.env.VITE_API_TIMEOUT || '10000', 10);
  const appEnv = import.meta.env.VITE_APP_ENV || import.meta.env.MODE || 'development';

  if (!apiUrl) {
    throw new Error(
      'VITE_API_URL environment variable is required. Please check your .env file.'
    );
  }

  // Remove trailing slash if present
  const normalizedApiUrl = apiUrl.replace(/\/$/, '');

  // Validate URL format
  try {
    new URL(normalizedApiUrl);
  } catch {
    throw new Error(
      `Invalid VITE_API_URL format: ${apiUrl}. Must be a valid URL.`
    );
  }

  if (isNaN(apiTimeout) || apiTimeout <= 0) {
    throw new Error(
      `Invalid VITE_API_TIMEOUT: ${apiTimeout}. Must be a positive number.`
    );
  }

  return {
    apiUrl: normalizedApiUrl,
    apiTimeout,
    appEnv,
    isDevelopment: appEnv === 'development',
    isProduction: appEnv === 'production',
  };
}

// Export validated configuration
export const env = getEnvConfig();

// Export individual values for convenience
export const API_URL = env.apiUrl;
export const API_TIMEOUT = env.apiTimeout;
export const APP_ENV = env.appEnv;
export const IS_DEVELOPMENT = env.isDevelopment;
export const IS_PRODUCTION = env.isProduction;

