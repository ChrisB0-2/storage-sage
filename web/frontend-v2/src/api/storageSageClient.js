import axios from 'axios'

// Use relative URL to go through the backend proxy (same origin as frontend)
// Backend serves frontend and proxies API requests to daemon
const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || ''

const apiClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
  },
})

// Add request interceptor for logging and JWT token
apiClient.interceptors.request.use(
  (config) => {
    console.log(`[API] ${config.method?.toUpperCase()} ${config.url}`)

    // Add JWT token to requests if available
    const token = localStorage.getItem('jwt_token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }

    return config
  },
  (error) => {
    console.error('[API] Request error:', error)
    return Promise.reject(error)
  }
)

// Add response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => {
    console.log(`[API] Response ${response.status} from ${response.config.url}`)
    return response
  },
  (error) => {
    const message = error.response?.data?.error || error.message
    console.error('[API] Response error:', message)
    return Promise.reject(error)
  }
)

/**
 * Login and get JWT token
 * @param {string} username - Username
 * @param {string} password - Password
 * @returns {Promise<Object>} Login response with token
 */
export const login = async (username, password) => {
  try {
    const response = await apiClient.post('/api/v1/auth/login', {
      username,
      password,
    })

    // Store token in localStorage
    if (response.data.token) {
      localStorage.setItem('jwt_token', response.data.token)
    }

    return response.data
  } catch (error) {
    throw new Error(`Login failed: ${error.message}`)
  }
}

/**
 * Logout and clear JWT token
 */
export const logout = () => {
  localStorage.removeItem('jwt_token')
}

/**
 * Check if user is authenticated
 * @returns {boolean} True if JWT token exists
 */
export const isAuthenticated = () => {
  return !!localStorage.getItem('jwt_token')
}

/**
 * Get system metrics (usage, thresholds, cleanup stats)
 * @returns {Promise<Object>} Metrics data
 */
export const getMetrics = async () => {
  try {
    const response = await apiClient.get('/api/v1/metrics/current')
    return response.data
  } catch (error) {
    throw new Error(`Failed to fetch metrics: ${error.message}`)
  }
}

/**
 * Get current configuration (global + per-path rules)
 * @returns {Promise<Object>} Configuration data
 */
export const getConfig = async () => {
  try {
    const response = await apiClient.get('/api/v1/config')
    return response.data
  } catch (error) {
    throw new Error(`Failed to fetch config: ${error.message}`)
  }
}

/**
 * Update configuration
 * @param {Object} config - New configuration object
 * @returns {Promise<Object>} Updated configuration
 */
export const updateConfig = async (config) => {
  try {
    const response = await apiClient.put('/api/v1/config', config)
    return response.data
  } catch (error) {
    throw new Error(`Failed to update config: ${error.message}`)
  }
}

/**
 * Get deletion history
 * @param {number} limit - Maximum number of records to return
 * @returns {Promise<Array>} Array of deletion records
 */
export const getDeletions = async (limit = 100) => {
  try {
    const response = await apiClient.get('/api/v1/deletions/log', {
      params: { limit },
    })
    return response.data
  } catch (error) {
    throw new Error(`Failed to fetch deletions: ${error.message}`)
  }
}

/**
 * Trigger manual cleanup run
 * @returns {Promise<Object>} Cleanup result
 */
export const triggerCleanup = async () => {
  try {
    const response = await apiClient.post('/api/v1/cleanup/trigger')
    return response.data
  } catch (error) {
    throw new Error(`Failed to trigger cleanup: ${error.message}`)
  }
}

/**
 * Health check endpoint
 * @returns {Promise<Object>} Health status
 */
export const getHealth = async () => {
  try {
    const response = await apiClient.get('/api/v1/health')
    return response.data
  } catch (error) {
    throw new Error(`Failed to fetch health: ${error.message}`)
  }
}

export default {
  login,
  logout,
  isAuthenticated,
  getMetrics,
  getConfig,
  updateConfig,
  getDeletions,
  triggerCleanup,
  getHealth,
}
