#!/bin/bash
# Test W15: Security Headers in HEAD Requests
# Verifies the fix for HEAD request security headers

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BACKEND_URL="${BACKEND_URL:-https://localhost:8443}"
HEALTH_ENDPOINT="${BACKEND_URL}/api/v1/health"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  W15 Security Headers Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check if backend is running
echo -n "1. Checking if backend is running... "
if docker compose ps storage-sage-backend 2>/dev/null | grep -q "Up"; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo ""
    echo -e "${YELLOW}Backend is not running. Starting it now...${NC}"
    docker compose up -d storage-sage-backend
    sleep 10
fi

# Step 2: Check if backend needs rebuild
echo -n "2. Checking if backend needs rebuild... "
ROUTES_HASH=$(md5sum web/backend/api/routes.go | cut -d' ' -f1)
CONTAINER_ID=$(docker compose ps -q storage-sage-backend 2>/dev/null || echo "")

if [ -z "$CONTAINER_ID" ]; then
    echo -e "${YELLOW}! Container not found, will rebuild${NC}"
    NEEDS_REBUILD=true
else
    # Check if the container was created recently (within last hour)
    CONTAINER_AGE=$(docker inspect --format='{{.Created}}' "$CONTAINER_ID" 2>/dev/null || echo "")
    if [ -n "$CONTAINER_AGE" ]; then
        CREATED_TIMESTAMP=$(date -d "$CONTAINER_AGE" +%s 2>/dev/null || echo "0")
        CURRENT_TIMESTAMP=$(date +%s)
        AGE_SECONDS=$((CURRENT_TIMESTAMP - CREATED_TIMESTAMP))

        if [ "$AGE_SECONDS" -lt 3600 ]; then
            echo -e "${GREEN}✓ Recently rebuilt${NC}"
            NEEDS_REBUILD=false
        else
            echo -e "${YELLOW}! Container is old, rebuilding${NC}"
            NEEDS_REBUILD=true
        fi
    else
        echo -e "${YELLOW}! Cannot determine age, rebuilding${NC}"
        NEEDS_REBUILD=true
    fi
fi

# Step 3: Rebuild if needed
if [ "$NEEDS_REBUILD" = true ]; then
    echo ""
    echo -e "${BLUE}3. Rebuilding backend with fix...${NC}"
    docker compose build storage-sage-backend
    echo -e "${GREEN}   ✓ Build complete${NC}"

    echo ""
    echo -e "${BLUE}4. Restarting backend...${NC}"
    docker compose up -d storage-sage-backend
    echo -e "${GREEN}   ✓ Backend restarted${NC}"

    echo ""
    echo -n "5. Waiting for backend to be ready (30s)... "
    sleep 30
    echo -e "${GREEN}✓ Done${NC}"
else
    echo ""
fi

# Step 4: Test GET request (baseline)
echo ""
echo -e "${BLUE}Testing GET request (baseline):${NC}"
echo -e "${BLUE}========================================${NC}"
GET_RESPONSE=$(curl -sk https://localhost:8443/api/v1/health 2>&1)
if echo "$GET_RESPONSE" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ GET request works${NC}"
else
    echo -e "${RED}✗ GET request failed${NC}"
    echo "Response: $GET_RESPONSE"
    exit 1
fi

# Step 5: Test HEAD request with verbose output
echo ""
echo -e "${BLUE}Testing HEAD request (verbose):${NC}"
echo -e "${BLUE}========================================${NC}"
HEAD_RESPONSE=$(curl -vkI https://localhost:8443/api/v1/health 2>&1)
echo "$HEAD_RESPONSE"

# Step 6: Check for security headers
echo ""
echo -e "${BLUE}Checking for security headers:${NC}"
echo -e "${BLUE}========================================${NC}"

HEADERS_FOUND=0
HEADERS_MISSING=0

# Check X-Content-Type-Options
echo -n "X-Content-Type-Options: "
if echo "$HEAD_RESPONSE" | grep -qi "X-Content-Type-Options"; then
    VALUE=$(echo "$HEAD_RESPONSE" | grep -i "X-Content-Type-Options" | cut -d':' -f2- | tr -d '\r' | xargs)
    echo -e "${GREEN}✓ $VALUE${NC}"
    ((HEADERS_FOUND++))
else
    echo -e "${RED}✗ MISSING${NC}"
    ((HEADERS_MISSING++))
fi

# Check X-Frame-Options
echo -n "X-Frame-Options: "
if echo "$HEAD_RESPONSE" | grep -qi "X-Frame-Options"; then
    VALUE=$(echo "$HEAD_RESPONSE" | grep -i "X-Frame-Options" | cut -d':' -f2- | tr -d '\r' | xargs)
    echo -e "${GREEN}✓ $VALUE${NC}"
    ((HEADERS_FOUND++))
else
    echo -e "${RED}✗ MISSING${NC}"
    ((HEADERS_MISSING++))
fi

# Check Strict-Transport-Security
echo -n "Strict-Transport-Security: "
if echo "$HEAD_RESPONSE" | grep -qi "Strict-Transport-Security"; then
    VALUE=$(echo "$HEAD_RESPONSE" | grep -i "Strict-Transport-Security" | cut -d':' -f2- | tr -d '\r' | xargs)
    echo -e "${GREEN}✓ $VALUE${NC}"
    ((HEADERS_FOUND++))
else
    echo -e "${RED}✗ MISSING${NC}"
    ((HEADERS_MISSING++))
fi

# Check X-XSS-Protection
echo -n "X-XSS-Protection: "
if echo "$HEAD_RESPONSE" | grep -qi "X-XSS-Protection"; then
    VALUE=$(echo "$HEAD_RESPONSE" | grep -i "X-XSS-Protection" | cut -d':' -f2- | tr -d '\r' | xargs)
    echo -e "${GREEN}✓ $VALUE${NC}"
    ((HEADERS_FOUND++))
else
    echo -e "${RED}✗ MISSING${NC}"
    ((HEADERS_MISSING++))
fi

# Check Content-Security-Policy
echo -n "Content-Security-Policy: "
if echo "$HEAD_RESPONSE" | grep -qi "Content-Security-Policy"; then
    VALUE=$(echo "$HEAD_RESPONSE" | grep -i "Content-Security-Policy" | cut -d':' -f2- | tr -d '\r' | xargs)
    echo -e "${GREEN}✓ ${VALUE:0:50}...${NC}"
    ((HEADERS_FOUND++))
else
    echo -e "${RED}✗ MISSING${NC}"
    ((HEADERS_MISSING++))
fi

# Step 7: Final result
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Test Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Security headers found: $HEADERS_FOUND"
echo "Security headers missing: $HEADERS_MISSING"
echo ""

# Step 8: Run the actual W15 test command
echo -e "${BLUE}Running W15 test command:${NC}"
TEST_CMD='curl -sk -I https://localhost:8443/api/v1/health | grep -qE '"'"'(X-Content-Type-Options|X-Frame-Options|Strict-Transport-Security)'"'"
echo "$ $TEST_CMD"
echo ""

if curl -sk -I https://localhost:8443/api/v1/health | grep -qE '(X-Content-Type-Options|X-Frame-Options|Strict-Transport-Security)'; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ✅ W15 TEST PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  ❌ W15 TEST FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check backend logs: docker compose logs --tail=50 storage-sage-backend"
    echo "2. Verify middleware order in web/backend/api/server.go"
    echo "3. Rebuild and restart: docker compose build storage-sage-backend && docker compose up -d storage-sage-backend"
    exit 1
fi
