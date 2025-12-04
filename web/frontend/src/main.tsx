import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './index.css'

// Validate environment configuration on startup
// Import env config to trigger validation (will throw if invalid)
try {
  // This import will throw if environment variables are invalid
  import('./config/env').then(() => {
    const rootElement = document.getElementById('root');
    if (!rootElement) {
      throw new Error('Root element not found');
    }
    
    ReactDOM.createRoot(rootElement).render(
      <React.StrictMode>
        <App />
      </React.StrictMode>,
    );
  }).catch((error: Error) => {
    // Display configuration error to user
    const root = document.getElementById('root');
    if (root) {
      const errorMessage = error?.message || 'Unknown configuration error';
      root.innerHTML = `
        <div style="display: flex; align-items: center; justify-content: center; min-height: 100vh; background: #111827; color: #ef4444; font-family: system-ui, sans-serif; padding: 2rem;">
          <div style="max-width: 600px; text-align: center;">
            <h1 style="font-size: 1.5rem; margin-bottom: 1rem;">Configuration Error</h1>
            <p style="margin-bottom: 1rem; word-break: break-word;">${errorMessage}</p>
            <p style="font-size: 0.875rem; color: #9ca3af; margin-top: 1rem;">
              Please check your .env file and ensure VITE_API_URL is set correctly.
              <br />
              See .env.example for reference.
            </p>
          </div>
        </div>
      `;
    }
    console.error('Environment configuration error:', error);
  });
} catch (error: any) {
  // Fallback for synchronous errors
  const root = document.getElementById('root');
  if (root) {
    root.innerHTML = `
      <div style="display: flex; align-items: center; justify-content: center; min-height: 100vh; background: #111827; color: #ef4444; font-family: system-ui, sans-serif; padding: 2rem;">
        <div style="max-width: 600px; text-align: center;">
          <h1 style="font-size: 1.5rem; margin-bottom: 1rem;">Configuration Error</h1>
          <p style="margin-bottom: 1rem; word-break: break-word;">${error?.message || 'Unknown configuration error'}</p>
          <p style="font-size: 0.875rem; color: #9ca3af; margin-top: 1rem;">
            Please check your .env file and ensure all required variables are set.
          </p>
        </div>
      </div>
    `;
  }
  console.error('Environment configuration error:', error);
}
