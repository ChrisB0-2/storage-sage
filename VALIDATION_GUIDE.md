# StorageSage Validation Guide

Quick guide to validate all security fixes and test infrastructure improvements.

## Prerequisites

```bash
cd /home/user/projects/storage-sage

# Ensure you have the JWT secret file
openssl rand -base64 32 > secrets/jwt_secret.txt

# Build and start services
docker compose build
docker compose up -d
```

## Validation Tests

### 1. Test Infrastructure Fix ✅

**Test:** Verify timestamps are set correctly inside container

```bash
# Run comprehensive test suite
./scripts/test-active-server.sh

# What to look for:
# ✓ "Timestamps set inside container (XX files >7 days old)" - XX should be >80
# ✓ "Files deleted: 90+" in Phase 2 (age-based cleanup)
# ✓ Overall test pass rate >90%
```

**Expected Output:**
```
[TEST] Set file timestamps inside container to ensure preservation
  Files >7 days old: 88
  Files >14 days old: 73
  ✓ PASS: Timestamps set inside container (88 files >7 days old)

Phase 2: Age-Based Cleanup Test
  Files deleted: 94
  ✓ PASS: Age-based cleanup deleted expected number of files (94)
```

### 2. JWT Secrets (Docker Secrets) ✅

**Test:** Verify backend reads from Docker secrets

```bash
# Check backend logs
docker compose logs storage-sage-backend | grep -i "jwt secret"

# Expected output:
# "Loaded JWT secret from file (Docker secrets)"
# NOT: "WARNING: Using default JWT secret"
```

**Test:** Verify secret file is mounted

```bash
docker compose exec storage-sage-backend cat /run/secrets/jwt_secret

# Should output your JWT secret (base64 string)
```

**Test:** Verify authentication works

```bash
# Login (should succeed)
curl -k -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Expected: JSON with token
# {"token":"eyJhbGc...","user":{"username":"admin","role":"admin"}}
```

### 3. Rate Limiting ✅

**Test:** Trigger rate limit on login endpoint

```bash
# Send 20 rapid requests (limit is 5/sec with burst of 10)
for i in {1..20}; do
  curl -k -s -w "\nStatus: %{http_code}\n" -X POST \
    https://localhost:8443/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"test","password":"test"}' &
done | grep "Status:"

# Expected: Mix of 401 (unauthorized) and 429 (rate limited)
# Status: 401  (first 10 requests)
# Status: 429  (requests 11-20 - rate limited)
```

**Test:** Verify global rate limiting

```bash
# Send many requests to health endpoint (global limit: 100/sec)
for i in {1..150}; do
  curl -k -s -w "%{http_code}\n" -o /dev/null \
    https://localhost:8443/api/v1/health &
done | sort | uniq -c

# Expected: Most 200s, some 429s if exceeded burst
```

### 4. Input Size Limits ✅

**Test:** Send oversized request (>1MB limit)

```bash
# Get a valid JWT token first
TOKEN=$(curl -k -s -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | jq -r '.token')

# Send 2MB request (exceeds 1MB limit)
dd if=/dev/zero bs=1M count=2 2>/dev/null | \
  curl -k -s -w "\nHTTP Status: %{http_code}\n" -X POST \
    https://localhost:8443/api/v1/config \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @-

# Expected: HTTP Status: 413 (Request Entity Too Large)
```

**Test:** Normal-sized request should work

```bash
# Send small config update (<1MB)
curl -k -s -w "\nHTTP Status: %{http_code}\n" -X POST \
  https://localhost:8443/api/v1/config/validate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"test":"data"}'

# Expected: HTTP Status: 200 or 400 (not 413)
```

### 5. SystemD Security Hardening ✅

**Test:** Verify service user setup (requires sudo)

```bash
# Run setup script
sudo ./scripts/setup-systemd-user.sh

# Verify user was created
id storage-sage
# Expected: uid=XXX(storage-sage) gid=XXX(storage-sage) groups=XXX(storage-sage)

# Check user has no login shell
getent passwd storage-sage | cut -d: -f7
# Expected: /usr/sbin/nologin
```

**Test:** Verify service file security options

```bash
# Check service file exists
cat storage-sage.service | grep -A 5 "Security hardening"

# Expected to see:
# NoNewPrivileges=true
# ProtectSystem=strict
# ProtectHome=true
# etc.
```

**Test:** Install and check service (requires sudo and binary)

```bash
# Note: This requires the binary to be built and installed first
# sudo cp /path/to/storage-sage /usr/local/bin/
# sudo systemctl enable storage-sage
# sudo systemctl start storage-sage

# Check service is running as non-root
sudo systemctl status storage-sage | grep "Main PID"
ps -u storage-sage
# Should show storage-sage process
```

### 6. Docker Container Security ✅

**Test:** Verify non-root execution

```bash
# Check daemon runs as non-root
docker compose exec storage-sage-daemon id
# Expected: uid=1000 gid=1000 groups=1000

# Check backend runs as non-root
docker compose exec storage-sage-backend id
# Expected: uid=1000 gid=1000 groups=1000
```

**Test:** Verify security options

```bash
docker inspect storage-sage-daemon | jq '.[0].HostConfig.SecurityOpt'
# Expected: ["no-new-privileges:true"]

docker inspect storage-sage-backend | jq '.[0].HostConfig.SecurityOpt'
# Expected: ["no-new-privileges:true"]
```

## Complete Validation Script

Run all tests at once:

```bash
#!/bin/bash
set -e

echo "StorageSage Validation Tests"
echo "============================"
echo ""

# 1. Test Infrastructure
echo "1. Testing infrastructure (timestamps)..."
./scripts/test-active-server.sh 2>&1 | grep -E "(PASS|FAIL|Files deleted:)"
echo ""

# 2. JWT Secrets
echo "2. Testing JWT secrets..."
docker compose logs storage-sage-backend 2>&1 | grep -i "jwt secret" | tail -1
echo ""

# 3. Rate Limiting
echo "3. Testing rate limiting..."
echo "Sending 20 rapid requests..."
for i in {1..20}; do
  curl -k -s -w "%{http_code}\n" -o /dev/null -X POST \
    https://localhost:8443/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"test","password":"test"}' &
done | sort | uniq -c
echo ""

# 4. Input Size Limits
echo "4. Testing input size limits..."
TOKEN=$(curl -k -s -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | jq -r '.token')

dd if=/dev/zero bs=1M count=2 2>/dev/null | \
  curl -k -s -w "HTTP Status: %{http_code}\n" -o /dev/null -X POST \
    https://localhost:8443/api/v1/config \
    -H "Authorization: Bearer $TOKEN" \
    --data-binary @-
echo ""

# 5. Container Security
echo "5. Testing container security..."
echo "Daemon user:"
docker compose exec -T storage-sage-daemon id
echo "Backend user:"
docker compose exec -T storage-sage-backend id
echo ""

echo "All validation tests complete!"
```

Save as `scripts/validate-all.sh` and run:
```bash
chmod +x scripts/validate-all.sh
./scripts/validate-all.sh
```

## Troubleshooting

### Issue: "Cannot connect to daemon"
```bash
# Ensure services are running
docker compose ps

# Restart if needed
docker compose down
docker compose up -d

# Check logs
docker compose logs storage-sage-daemon
```

### Issue: "JWT secret not found"
```bash
# Generate secret
openssl rand -base64 32 > secrets/jwt_secret.txt

# Verify it exists
cat secrets/jwt_secret.txt

# Restart backend
docker compose restart storage-sage-backend
```

### Issue: "Test files not being deleted"
```bash
# Check daemon logs
docker compose logs storage-sage-daemon | grep -i "candidates_found"

# Verify config includes test workspace
docker compose exec storage-sage-daemon cat /etc/storage-sage/config.yaml | grep -A 5 "scan_paths"

# Manually trigger cleanup
docker compose exec storage-sage-daemon pkill -SIGUSR1 storage-sage
```

## Success Criteria

✅ All tests in `scripts/test-active-server.sh` pass (>90% pass rate)
✅ Backend logs show "Loaded JWT secret from file"
✅ Rate limiting returns HTTP 429 after burst
✅ Oversized requests return HTTP 413
✅ Containers run as UID 1000 (non-root)
✅ SystemD service configured with security hardening

If all criteria are met, **StorageSage is production-ready!**
