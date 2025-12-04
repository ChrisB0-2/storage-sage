#!/bin/bash
# Debug script to diagnose security header issues
# Usage: ./scripts/debug_headers.sh

set -e

BACKEND_URL="${BACKEND_URL:-https://localhost:8443}"

echo "========================================"
echo "  SECURITY HEADERS DIAGNOSTIC"
echo "========================================"
echo "Backend URL: $BACKEND_URL"
echo ""

echo "1. Testing connectivity to backend..."
if curl -sk --max-time 5 "$BACKEND_URL/api/v1/health" > /dev/null 2>&1; then
    echo "   ✓ Backend is reachable"
else
    echo "   ✗ Backend is NOT reachable"
    echo "   Ensure backend is running: docker-compose ps storage-sage-backend"
    exit 1
fi
echo ""

echo "2. Fetching ALL headers from /api/v1/health..."
echo "   Command: curl -sk -I $BACKEND_URL/api/v1/health"
echo "   ---"
curl -sk -I "$BACKEND_URL/api/v1/health" 2>&1 | head -20
echo "   ---"
echo ""

echo "3. Checking for specific security headers (case-insensitive)..."
HEADERS=$(curl -sk -I "$BACKEND_URL/api/v1/health" 2>&1)

echo -n "   X-Content-Type-Options: "
if echo "$HEADERS" | grep -qi "x-content-type-options:"; then
    VALUE=$(echo "$HEADERS" | grep -i "x-content-type-options:" | cut -d: -f2- | tr -d '\r\n' | xargs)
    echo "✓ PRESENT (value: $VALUE)"
else
    echo "✗ MISSING"
fi

echo -n "   X-Frame-Options: "
if echo "$HEADERS" | grep -qi "x-frame-options:"; then
    VALUE=$(echo "$HEADERS" | grep -i "x-frame-options:" | cut -d: -f2- | tr -d '\r\n' | xargs)
    echo "✓ PRESENT (value: $VALUE)"
else
    echo "✗ MISSING"
fi

echo -n "   Strict-Transport-Security: "
if echo "$HEADERS" | grep -qi "strict-transport-security:"; then
    VALUE=$(echo "$HEADERS" | grep -i "strict-transport-security:" | cut -d: -f2- | tr -d '\r\n' | xargs)
    echo "✓ PRESENT (value: $VALUE)"
else
    echo "✗ MISSING"
fi

echo -n "   X-XSS-Protection: "
if echo "$HEADERS" | grep -qi "x-xss-protection:"; then
    VALUE=$(echo "$HEADERS" | grep -i "x-xss-protection:" | cut -d: -f2- | tr -d '\r\n' | xargs)
    echo "✓ PRESENT (value: $VALUE)"
else
    echo "✗ MISSING"
fi

echo -n "   Content-Security-Policy: "
if echo "$HEADERS" | grep -qi "content-security-policy:"; then
    VALUE=$(echo "$HEADERS" | grep -i "content-security-policy:" | cut -d: -f2- | tr -d '\r\n' | xargs)
    echo "✓ PRESENT (value: ${VALUE:0:50}...)"
else
    echo "✗ MISSING"
fi
echo ""

echo "4. Testing with GET request (not HEAD)..."
echo "   Command: curl -sk -v $BACKEND_URL/api/v1/health 2>&1 | grep -i '< '"
curl -sk -v "$BACKEND_URL/api/v1/health" 2>&1 | grep -i '< ' | head -15
echo ""

echo "5. Checking backend container logs for errors..."
if docker ps --format '{{.Names}}' | grep -q 'storage-sage-backend'; then
    echo "   Last 10 lines of backend logs:"
    docker logs storage-sage-backend --tail 10 2>&1 | sed 's/^/   /'
else
    echo "   ✗ Backend container not running"
    echo "   Start with: docker-compose up -d storage-sage-backend"
fi
echo ""

echo "6. Verifying middleware configuration in server.go..."
if docker exec storage-sage-backend grep -n "SecurityHeadersMiddleware" /app/server.go 2>/dev/null; then
    echo "   ✓ SecurityHeadersMiddleware is registered"
else
    echo "   ✗ SecurityHeadersMiddleware NOT found in server.go"
    echo "   This is a critical configuration error"
fi
echo ""

echo "========================================"
echo "  DIAGNOSTIC COMPLETE"
echo "========================================"
echo ""
echo "If all headers show ✗ MISSING but backend is reachable:"
echo "  - Check if middleware is properly imported and applied"
echo "  - Verify router.Use(middleware.SecurityHeadersMiddleware) exists"
echo "  - Rebuild backend: docker-compose build --no-cache storage-sage-backend"
echo ""
echo "If backend is not reachable:"
echo "  - Check if containers are running: docker-compose ps"
echo "  - Check for port conflicts: netstat -tlnp | grep 8443"
echo "  - View logs: docker-compose logs storage-sage-backend"
