# Environment Configuration

The StorageSage frontend uses environment variables for configuration. This allows different settings for development, staging, and production environments.

## Setup

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Update the values in `.env` with your configuration:
   ```env
   VITE_API_URL=https://localhost:8443/api/v1
   VITE_API_TIMEOUT=10000
   VITE_APP_ENV=development
   ```

## Environment Variables

### Required Variables

- **VITE_API_URL**: Base URL for the API (without trailing slash)
  - Example: `https://localhost:8443/api/v1`
  - Must be a valid URL

### Optional Variables

- **VITE_API_TIMEOUT**: API request timeout in milliseconds (default: 10000)
- **VITE_APP_ENV**: Application environment (default: development)
  - Values: `development`, `production`, `staging`

## Validation

The application validates environment variables on startup. If required variables are missing or invalid, the application will display an error message and refuse to start.

## Production Deployment

For production deployments, set environment variables in your deployment environment (Docker, Kubernetes, etc.) rather than using a `.env` file.

**Note**: Never commit `.env` files to version control. The `.env` file is already in `.gitignore`.

