#!/bin/bash
# Debug script to diagnose Promtail connectivity and health issues
# Usage: ./scripts/debug_promtail.sh

set -e

PROMTAIL_URL="${PROMTAIL_URL:-http://localhost:9080}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"

echo "========================================"
echo "  PROMTAIL DIAGNOSTIC TOOL"
echo "========================================"
echo "Promtail URL: $PROMTAIL_URL"
echo "Loki URL: $LOKI_URL"
echo ""

# 1. Check if Promtail container is running
echo "1. Checking Promtail container status..."
if docker ps --format '{{.Names}}' | grep -q 'storage-sage-promtail'; then
    echo "   ✓ Promtail container is RUNNING"

    # Get container details
    echo ""
    echo "   Container details:"
    docker ps --filter "name=storage-sage-promtail" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sed 's/^/     /'
else
    echo "   ✗ Promtail container is NOT running"
    echo ""
    echo "   Checking if container exists (stopped)..."
    if docker ps -a --format '{{.Names}}' | grep -q 'storage-sage-promtail'; then
        echo "   ⚠ Container exists but is stopped"
        echo "   Status:"
        docker ps -a --filter "name=storage-sage-promtail" --format "table {{.Names}}\t{{.Status}}" | sed 's/^/     /'
        echo ""
        echo "   Start with: docker-compose up -d promtail"
    else
        echo "   ✗ Container does not exist"
        echo "   Create with: docker-compose up -d promtail"
    fi
    exit 1
fi
echo ""

# 2. Check Docker health status
echo "2. Checking Docker health status..."
HEALTH=$(docker inspect storage-sage-promtail --format='{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
echo "   Health status: $HEALTH"
if [ "$HEALTH" = "healthy" ]; then
    echo "   ✓ Container is HEALTHY"
elif [ "$HEALTH" = "starting" ]; then
    echo "   ⚠ Container is STARTING (wait 10-15 seconds)"
elif [ "$HEALTH" = "unhealthy" ]; then
    echo "   ✗ Container is UNHEALTHY"
    echo ""
    echo "   Last 5 health check logs:"
    docker inspect storage-sage-promtail --format='{{range .State.Health.Log}}{{.Output}}{{end}}' | tail -5 | sed 's/^/     /'
else
    echo "   ⚠ No health check configured or status unknown"
fi
echo ""

# 3. Check port binding
echo "3. Checking port 9080 binding..."
if netstat -tuln 2>/dev/null | grep -q ':9080'; then
    echo "   ✓ Port 9080 is bound"
    netstat -tuln | grep ':9080' | sed 's/^/     /'
elif ss -tuln 2>/dev/null | grep -q ':9080'; then
    echo "   ✓ Port 9080 is bound"
    ss -tuln | grep ':9080' | sed 's/^/     /'
else
    echo "   ✗ Port 9080 is NOT bound"
    echo "   Check docker-compose port mapping"
fi
echo ""

# 4. Test connectivity to Promtail
echo "4. Testing connectivity to Promtail..."
echo -n "   Attempting to reach $PROMTAIL_URL... "
if curl -s --max-time 5 "$PROMTAIL_URL" > /dev/null 2>&1; then
    echo "✓ REACHABLE"
else
    echo "✗ UNREACHABLE"
    echo ""
    echo "   Troubleshooting:"
    echo "   - Check if container is running: docker ps | grep promtail"
    echo "   - Check container logs: docker logs storage-sage-promtail"
    echo "   - Verify port mapping: docker port storage-sage-promtail"
    exit 1
fi
echo ""

# 5. Test /ready endpoint
echo "5. Testing /ready endpoint..."
echo "   Command: curl -s $PROMTAIL_URL/ready"
echo ""

for attempt in 1 2 3; do
    echo "   Attempt $attempt/3..."
    RESPONSE=$(curl -s --max-time 5 "$PROMTAIL_URL/ready" 2>&1)

    if echo "$RESPONSE" | grep -q 'ready'; then
        echo "   ✓ SUCCESS: Endpoint returned 'ready'"
        echo "   Response: $RESPONSE"
        break
    else
        echo "   ✗ FAIL: Did not receive 'ready' response"
        echo "   Response: ${RESPONSE:0:100}"

        if [ $attempt -lt 3 ]; then
            echo "   Waiting 2 seconds before retry..."
            sleep 2
        else
            echo ""
            echo "   ⚠ All attempts failed"
        fi
    fi
done
echo ""

# 6. Test /metrics endpoint
echo "6. Testing /metrics endpoint..."
echo -n "   Checking if metrics are exposed... "
if curl -s --max-time 5 "$PROMTAIL_URL/metrics" 2>&1 | grep -q 'promtail_'; then
    echo "✓ AVAILABLE"
    echo "   Sample metrics:"
    curl -s --max-time 5 "$PROMTAIL_URL/metrics" | grep 'promtail_' | head -5 | sed 's/^/     /'
else
    echo "✗ NOT AVAILABLE"
fi
echo ""

# 7. Check Loki connectivity (Promtail needs Loki to be ready)
echo "7. Checking Loki connectivity (Promtail dependency)..."
echo -n "   Testing Loki at $LOKI_URL/ready... "
if curl -s --max-time 5 "$LOKI_URL/ready" 2>&1 | grep -q 'ready'; then
    echo "✓ LOKI IS READY"
else
    echo "✗ LOKI IS NOT READY"
    echo ""
    echo "   ⚠ Promtail requires Loki to be running and ready"
    echo "   Check Loki status: docker logs storage-sage-loki --tail 20"
    echo "   Start Loki: docker-compose up -d loki"
fi
echo ""

# 8. Check Promtail logs
echo "8. Checking Promtail logs (last 20 lines)..."
echo "   ---"
docker logs storage-sage-promtail --tail 20 2>&1 | sed 's/^/   /'
echo "   ---"
echo ""

# 9. Check configuration
echo "9. Verifying Promtail configuration..."
if docker exec storage-sage-promtail test -f /etc/promtail/config.yml 2>/dev/null; then
    echo "   ✓ Config file exists in container"

    echo ""
    echo "   Checking HTTP listen port in config..."
    if docker exec storage-sage-promtail grep -q 'http_listen_port: 9080' /etc/promtail/config.yml 2>/dev/null; then
        echo "   ✓ http_listen_port is correctly set to 9080"
    else
        echo "   ✗ http_listen_port is NOT set to 9080"
        echo "   Current config:"
        docker exec storage-sage-promtail grep 'http_listen_port' /etc/promtail/config.yml 2>/dev/null | sed 's/^/     /'
    fi

    echo ""
    echo "   Checking Loki client URL..."
    docker exec storage-sage-promtail grep 'url:' /etc/promtail/config.yml 2>/dev/null | sed 's/^/     /'
else
    echo "   ✗ Config file NOT found in container"
    echo "   Check volume mount: ./promtail-config.yml:/etc/promtail/config.yml"
fi
echo ""

# 10. Network connectivity from container
echo "10. Testing network from within Promtail container..."
echo -n "   Can Promtail reach Loki? "
if docker exec storage-sage-promtail wget -q -O- --timeout=5 http://loki:3100/ready 2>/dev/null | grep -q 'ready'; then
    echo "✓ YES"
else
    echo "✗ NO"
    echo "   This may prevent Promtail from becoming ready"
    echo "   Check Docker network: docker network inspect storage-sage-network"
fi
echo ""

echo "========================================"
echo "  DIAGNOSTIC COMPLETE"
echo "========================================"
echo ""
echo "Common issues and solutions:"
echo ""
echo "1. Promtail not ready:"
echo "   - Ensure Loki is running and ready first"
echo "   - Wait 10-15 seconds after starting containers"
echo "   - Check logs: docker logs storage-sage-promtail"
echo ""
echo "2. Port 9080 not accessible:"
echo "   - Check port mapping: docker port storage-sage-promtail"
echo "   - Verify no firewall blocking: sudo iptables -L | grep 9080"
echo "   - Check for port conflicts: netstat -tlnp | grep 9080"
echo ""
echo "3. /ready endpoint returns error:"
echo "   - Verify Loki is accessible from Promtail container"
echo "   - Check Promtail config: docker exec storage-sage-promtail cat /etc/promtail/config.yml"
echo "   - Restart: docker-compose restart promtail"
