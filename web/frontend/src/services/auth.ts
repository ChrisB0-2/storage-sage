import axios, { AxiosError } from 'axios';
import { API_URL } from '../config/env';

interface LoginResponse {
  token: string;
  expires_at?: string;
  user: {
    username: string;
    roles: string[];
  };
}

// TokenData interface - reserved for future use
// interface TokenData {
//   token: string;
//   expiresAt?: number; // Unix timestamp in milliseconds
//   storedAt: number; // When token was stored
// }

class AuthService {
  private tokenKey = 'storage_sage_token';
  private expiryKey = 'storage_sage_token_expiry';
  private readonly TOKEN_REFRESH_THRESHOLD = 5 * 60 * 1000; // 5 minutes before expiry
  private readonly SESSION_WARNING_TIME = 10 * 60 * 1000; // Warn 10 minutes before expiry

  async login(username: string, password: string): Promise<LoginResponse> {
    try {
      const response = await axios.post<LoginResponse>(
        `${API_URL}/auth/login`,
        { username, password }
      );

      if (response.data.token) {
        this.setToken(response.data.token, response.data.expires_at);
      }

      return response.data;
    } catch (error) {
      // Log error details only in development
      if (import.meta.env.DEV) {
        console.error('Login error:', error);
      }

      // Handle network/certificate errors
      if (error instanceof AxiosError) {
        if (
          error.message?.includes('Network Error') ||
          error.message?.includes('ERR_CERT') ||
          error.code === 'ERR_CERT_AUTHORITY_INVALID'
        ) {
          throw new Error(
            `Cannot connect to server. Please visit ${API_URL}/health and accept the security certificate first.`
          );
        }
        // Handle 401 Unauthorized
        if (error.response?.status === 401) {
          throw new Error('Invalid username or password.');
        }
        // Handle other HTTP errors
        if (error.response?.status) {
          throw new Error(
            `Login failed: ${error.response.statusText || 'Server error'}`
          );
        }
      }

      // Generic error fallback
      throw new Error('Login failed. Please check your credentials and try again.');
    }
  }

  /**
   * Store token with expiration information
   */
  private setToken(token: string, expiresAt?: string): void {
    localStorage.setItem(this.tokenKey, token);
    
    if (expiresAt) {
      const expiryTimestamp = new Date(expiresAt).getTime();
      localStorage.setItem(this.expiryKey, expiryTimestamp.toString());
    } else {
      // If no expiration provided, assume 24 hours from now
      const defaultExpiry = Date.now() + 24 * 60 * 60 * 1000;
      localStorage.setItem(this.expiryKey, defaultExpiry.toString());
    }
  }

  /**
   * Check if token is expired
   */
  private isTokenExpired(): boolean {
    const expiryStr = localStorage.getItem(this.expiryKey);
    if (!expiryStr) {
      // No expiry info means token might be expired or legacy token
      // For security, treat as expired if we can't verify
      return true;
    }

    const expiry = parseInt(expiryStr, 10);
    if (isNaN(expiry)) {
      return true;
    }

    return Date.now() >= expiry;
  }

  /**
   * Get time until token expires in milliseconds
   * Returns null if expired or no expiry info
   */
  getTimeUntilExpiry(): number | null {
    const expiryStr = localStorage.getItem(this.expiryKey);
    if (!expiryStr) {
      return null;
    }

    const expiry = parseInt(expiryStr, 10);
    if (isNaN(expiry)) {
      return null;
    }

    const timeUntil = expiry - Date.now();
    return timeUntil > 0 ? timeUntil : null;
  }

  /**
   * Check if token needs refresh (within threshold)
   */
  needsRefresh(): boolean {
    const timeUntil = this.getTimeUntilExpiry();
    if (timeUntil === null) {
      return true; // Expired or unknown
    }
    return timeUntil < this.TOKEN_REFRESH_THRESHOLD;
  }

  /**
   * Check if session warning should be shown
   */
  shouldShowSessionWarning(): boolean {
    const timeUntil = this.getTimeUntilExpiry();
    if (timeUntil === null) {
      return false;
    }
    return timeUntil < this.SESSION_WARNING_TIME && timeUntil > 0;
  }

  logout(): void {
    localStorage.removeItem(this.tokenKey);
    localStorage.removeItem(this.expiryKey);
  }

  getToken(): string | null {
    // Check if token is expired before returning
    if (this.isTokenExpired()) {
      this.logout();
      return null;
    }

    return localStorage.getItem(this.tokenKey);
  }

  getAuthHeader() {
    const token = this.getToken();
    return token ? { Authorization: `Bearer ${token}` } : {};
  }

  isAuthenticated(): boolean {
    const token = this.getToken();
    return !!token && !this.isTokenExpired();
  }
}

export const authService = new AuthService();

// Note: Axios interceptors are now handled in apiClient.ts
// This keeps authentication logic centralized
