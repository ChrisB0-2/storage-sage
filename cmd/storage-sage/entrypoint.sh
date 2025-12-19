#!/bin/sh
set -e

# Container entrypoint for storage-sage backend
# Generates TLS certificates at runtime in a writable location

# Default certificate paths (can be overridden via environment)
TLS_KEY_PATH="${TLS_KEY_PATH:-/tmp/certs/server.key}"
TLS_CERT_PATH="${TLS_CERT_PATH:-/tmp/certs/server.crt}"

# Extract directory from key path
CERT_DIR="$(dirname "$TLS_KEY_PATH")"

echo "=== Storage Sage Backend Startup ==="
echo "Certificate directory: $CERT_DIR"
echo "Key path: $TLS_KEY_PATH"
echo "Cert path: $TLS_CERT_PATH"
echo ""

# Check if certificates already exist (mounted from host or volume)
if [ -f "$TLS_KEY_PATH" ] && [ -f "$TLS_CERT_PATH" ]; then
    echo "✓ Using existing certificates"
    ls -la "$TLS_KEY_PATH" "$TLS_CERT_PATH" 2>/dev/null || true
else
    echo "Generating self-signed certificates..."

    # Create certificate directory
    mkdir -p "$CERT_DIR"

    # Generate certificates with restrictive permissions using umask
    # umask 077 ensures files are created with 600 (rw-------)
    (
        umask 077
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$TLS_KEY_PATH" \
            -out "$TLS_CERT_PATH" \
            -subj "/CN=localhost" \
            2>/dev/null
    )

    echo "✓ Certificates generated successfully"
    ls -la "$TLS_KEY_PATH" "$TLS_CERT_PATH" 2>/dev/null || true
fi

echo ""
echo "Starting storage-sage backend..."
echo ""

# Export certificate paths for the backend to use
export TLS_KEY_PATH
export TLS_CERT_PATH

# Determine which binary to execute (supports both storage-sage and storage-sage-web)
if [ -x "/app/storage-sage-web" ]; then
    exec /app/storage-sage-web "$@"
elif [ -x "/app/storage-sage" ]; then
    exec /app/storage-sage "$@"
else
    echo "ERROR: No executable found (looking for /app/storage-sage-web or /app/storage-sage)"
    exit 1
fi
