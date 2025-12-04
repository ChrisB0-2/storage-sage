#!/bin/bash
# Test script to verify security headers are present in HEAD requests

set -e

BACKEND_URL="${BACKEND_URL:-https://localhost:8443}"

echo "Testing security headers on /api/v1/health endpoint"
echo "Backend URL: $BACKEND_URL"
echo ""

echo "Making HEAD request..."
HEADERS=$(curl -sk -I "$BACKEND_URL/api/v1/health" 2>&1)

echo "Response headers:"
echo "$HEADERS"
echo ""

# Check for required security headers
echo "Checking for required security headers..."

if echo "$HEADERS" | grep -qi "X-Content-Type-Options"; then
    echo "✅ X-Content-Type-Options header present"
    echo "   Value: $(echo "$HEADERS" | grep -i "X-Content-Type-Options")"
else
    echo "❌ X-Content-Type-Options header MISSING"
    exit 1
fi

if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
    echo "✅ X-Frame-Options header present"
    echo "   Value: $(echo "$HEADERS" | grep -i "X-Frame-Options")"
else
    echo "❌ X-Frame-Options header MISSING"
    exit 1
fi

if echo "$HEADERS" | grep -qi "Strict-Transport-Security"; then
    echo "✅ Strict-Transport-Security header present"
    echo "   Value: $(echo "$HEADERS" | grep -i "Strict-Transport-Security")"
else
    echo "❌ Strict-Transport-Security header MISSING"
    exit 1
fi

echo ""
echo "🎉 All required security headers are present!"
echo ""

# Also test GET request to ensure we didn't break anything
echo "Testing GET request..."
RESPONSE=$(curl -sk "$BACKEND_URL/api/v1/health" 2>&1)
if echo "$RESPONSE" | grep -q "healthy"; then
    echo "✅ GET request works correctly"
else
    echo "❌ GET request failed"
    exit 1
fi

echo ""
echo "✅ All tests passed!"
