#!/bin/bash
# Diagnostic script for Q7 test failure
# Runs all checks to identify why database query tests are failing

set +e  # Don't exit on error

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Q7 Test Failure Diagnostics${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check 1: Container running
echo -e "${BLUE}[1/8]${NC} Checking if daemon container is running..."
if docker ps --format '{{.Names}}' | grep -q 'storage-sage-daemon'; then
    echo -e "  ${GREEN}✓${NC} Container is running"
    CONTAINER_STATUS="running"
else
    echo -e "  ${RED}✗${NC} Container is NOT running"
    echo -e "  ${YELLOW}Action: Run 'docker compose up -d storage-sage-daemon'${NC}"
    CONTAINER_STATUS="stopped"
    exit 1
fi
echo ""

# Check 2: Binary exists
echo -e "${BLUE}[2/8]${NC} Checking if storage-sage-query binary exists..."
if docker exec storage-sage-daemon which storage-sage-query >/dev/null 2>&1; then
    BINARY_PATH=$(docker exec storage-sage-daemon which storage-sage-query)
    echo -e "  ${GREEN}✓${NC} Binary found at: $BINARY_PATH"
    BINARY_STATUS="found"
else
    echo -e "  ${RED}✗${NC} Binary NOT found in PATH"
    echo -e "  ${YELLOW}Action: Rebuild container with 'docker compose build --no-cache storage-sage-daemon'${NC}"
    BINARY_STATUS="missing"
fi
echo ""

# Check 3: Binary permissions and ownership
if [ "$BINARY_STATUS" = "found" ]; then
    echo -e "${BLUE}[3/8]${NC} Checking binary permissions..."
    BINARY_INFO=$(docker exec storage-sage-daemon ls -la "$BINARY_PATH" 2>&1)
    echo "  $BINARY_INFO"
    if echo "$BINARY_INFO" | grep -q "storagesage"; then
        echo -e "  ${GREEN}✓${NC} Binary owned by storagesage user"
    else
        echo -e "  ${YELLOW}⚠${NC} Binary ownership may be incorrect"
    fi
else
    echo -e "${BLUE}[3/8]${NC} ${YELLOW}Skipped${NC} (binary not found)"
fi
echo ""

# Check 4: Database directory exists
echo -e "${BLUE}[4/8]${NC} Checking if database directory exists..."
if docker exec storage-sage-daemon test -d /var/lib/storage-sage; then
    DIR_INFO=$(docker exec storage-sage-daemon ls -ld /var/lib/storage-sage)
    echo -e "  ${GREEN}✓${NC} Directory exists"
    echo "  $DIR_INFO"
else
    echo -e "  ${RED}✗${NC} Directory does NOT exist"
    echo -e "  ${YELLOW}Creating directory...${NC}"
    docker exec storage-sage-daemon mkdir -p /var/lib/storage-sage
    echo -e "  ${GREEN}✓${NC} Directory created"
fi
echo ""

# Check 5: Database file exists
echo -e "${BLUE}[5/8]${NC} Checking if database file exists..."
if docker exec storage-sage-daemon test -f /var/lib/storage-sage/deletions.db; then
    DB_INFO=$(docker exec storage-sage-daemon ls -lh /var/lib/storage-sage/deletions.db)
    echo -e "  ${GREEN}✓${NC} Database exists"
    echo "  $DB_INFO"
    DB_STATUS="exists"
else
    echo -e "  ${YELLOW}⚠${NC} Database does NOT exist yet"
    echo "  This is normal if daemon hasn't initialized or no deletions have occurred"
    echo "  Database will be created on first query"
    DB_STATUS="missing"
fi
echo ""

# Check 6: Run query tool with --help
if [ "$BINARY_STATUS" = "found" ]; then
    echo -e "${BLUE}[6/8]${NC} Testing query tool help..."
    if docker exec storage-sage-daemon storage-sage-query --help >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Query tool responds to --help"
    else
        echo -e "  ${RED}✗${NC} Query tool fails on --help"
        echo "  Output:"
        docker exec storage-sage-daemon storage-sage-query --help 2>&1 | head -5 | sed 's/^/    /'
    fi
else
    echo -e "${BLUE}[6/8]${NC} ${YELLOW}Skipped${NC} (binary not found)"
fi
echo ""

# Check 7: Run actual stats query
if [ "$BINARY_STATUS" = "found" ]; then
    echo -e "${BLUE}[7/8]${NC} Running actual stats query..."
    echo "  Command: storage-sage-query --db /var/lib/storage-sage/deletions.db --stats"
    echo ""
    QUERY_OUTPUT=$(docker exec storage-sage-daemon storage-sage-query --db /var/lib/storage-sage/deletions.db --stats 2>&1)
    QUERY_EXIT=$?

    echo "  Output:"
    echo "$QUERY_OUTPUT" | sed 's/^/    /'
    echo ""

    if [ $QUERY_EXIT -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} Query executed successfully (exit code 0)"

        # Check if output contains expected patterns
        if echo "$QUERY_OUTPUT" | grep -qE '(Total Records|Database Statistics)'; then
            echo -e "  ${GREEN}✓${NC} Output contains expected pattern 'Total Records' or 'Database Statistics'"
        else
            echo -e "  ${YELLOW}⚠${NC} Output does NOT contain expected pattern"
            echo "  This may cause test Q7 to fail"
        fi
    else
        echo -e "  ${RED}✗${NC} Query failed with exit code $QUERY_EXIT"
    fi
else
    echo -e "${BLUE}[7/8]${NC} ${YELLOW}Skipped${NC} (binary not found)"
fi
echo ""

# Check 8: Daemon logs for database initialization
echo -e "${BLUE}[8/8]${NC} Checking daemon logs for database messages..."
DB_LOGS=$(docker logs storage-sage-daemon 2>&1 | grep -i database | tail -10)
if [ -n "$DB_LOGS" ]; then
    echo "  Recent database-related log entries:"
    echo "$DB_LOGS" | sed 's/^/    /'
else
    echo -e "  ${YELLOW}⚠${NC} No database-related log entries found"
    echo "  This may indicate the daemon hasn't attempted database operations yet"
fi
echo ""

# Summary and recommendations
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  SUMMARY & RECOMMENDATIONS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ "$CONTAINER_STATUS" = "stopped" ]; then
    echo -e "${RED}1. Start the daemon container:${NC}"
    echo "   docker compose up -d storage-sage-daemon"
    echo ""
fi

if [ "$BINARY_STATUS" = "missing" ]; then
    echo -e "${RED}2. Rebuild daemon image with query tool:${NC}"
    echo "   docker compose build --no-cache storage-sage-daemon"
    echo "   docker compose up -d storage-sage-daemon"
    echo ""
fi

if [ "$BINARY_STATUS" = "found" ] && [ "$DB_STATUS" = "missing" ]; then
    echo -e "${YELLOW}3. Database not initialized yet:${NC}"
    echo "   This is normal. Options:"
    echo "   a) Wait for daemon to create it during cleanup"
    echo "   b) Trigger manual cleanup to force creation:"
    echo "      curl -k -X POST -H 'Authorization: Bearer \$TOKEN' https://localhost:8443/api/v1/cleanup/trigger"
    echo "   c) Query tool will create empty DB automatically"
    echo ""
fi

if [ "$BINARY_STATUS" = "found" ] && [ $QUERY_EXIT -ne 0 ]; then
    echo -e "${RED}4. Query execution failed:${NC}"
    echo "   Check the query output above for error details"
    echo "   Common issues:"
    echo "   - Database corruption (recreate: rm deletions.db)"
    echo "   - Permission errors (check volume mount)"
    echo "   - SQLite version mismatch (rebuild image)"
    echo ""
fi

echo -e "${GREEN}Next steps:${NC}"
echo "1. Address any issues above"
echo "2. Re-run this diagnostic: ./scripts/diagnose_q7.sh"
echo "3. Run full test suite: ./scripts/comprehensive_test.sh"
echo ""
