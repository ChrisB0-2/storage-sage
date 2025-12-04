# How to Apply the Security Headers Fix

## Quick Start

### 1. Rebuild the Backend Container
```bash
# From the project root directory
docker-compose build storage-sage-backend --no-cache

# Or rebuild all services
docker-compose build --no-cache
```

### 2. Restart the Services
```bash
# Stop current containers
docker-compose down

# Start with the updated backend
docker-compose up -d

# Or restart just the backend
docker-compose restart storage-sage-backend
```

### 3. Verify the Fix

#### Option A: Use the Test Script
```bash
./test_security_headers.sh
```

Expected output:
```
Testing security headers on /api/v1/health endpoint
Backend URL: https://localhost:8443

Making HEAD request...
Response headers:
HTTP/2 200
...

Checking for required security headers...
✅ X-Content-Type-Options header present
   Value: X-Content-Type-Options: nosniff
✅ X-Frame-Options header present
   Value: X-Frame-Options: DENY
✅ Strict-Transport-Security header present
   Value: Strict-Transport-Security: max-age=31536000; includeSubDomains

🎉 All required security headers are present!

Testing GET request...
✅ GET request works correctly

✅ All tests passed!
```

#### Option B: Run Comprehensive Tests
```bash
./scripts/comprehensive_test.sh
```

Look for this test result:
```
[W15] Security headers present... ✅ PASS
```

#### Option C: Manual Verification
```bash
# Test HEAD request
curl -sk -I https://localhost:8443/api/v1/health

# You should see these headers in the output:
# X-Content-Type-Options: nosniff
# X-Frame-Options: DENY
# Strict-Transport-Security: max-age=31536000; includeSubDomains
```

## Troubleshooting

### Issue: Backend container won't start
```bash
# Check backend logs
docker-compose logs storage-sage-backend

# Look for any Go compilation errors
# The fix should compile cleanly - if not, check for syntax errors
```

### Issue: Headers still not appearing
```bash
# Ensure you rebuilt the container
docker-compose ps | grep backend

# Check the build timestamp is recent
docker images | grep storage-sage-backend

# Force rebuild if needed
docker-compose build storage-sage-backend --no-cache
docker-compose up -d storage-sage-backend
```

### Issue: Test script can't connect
```bash
# Check if backend is running
docker-compose ps storage-sage-backend

# Check backend is listening on 8443
docker-compose logs storage-sage-backend | grep "8443"

# Verify network connectivity
curl -sk https://localhost:8443/api/v1/health

# If using different host/port:
BACKEND_URL=https://your-host:8443 ./test_security_headers.sh
```

## What Changed

### File Modified
- `web/backend/api/routes.go` - Updated HealthHandler (lines 83-109)

### Change Summary
The HealthHandler now uses a defensive programming approach to ensure security headers are ALWAYS present in responses, even if middleware fails. This is especially important for HEAD requests which had been failing the security header test.

### Why Rebuild?
Go is a compiled language, so changes to `.go` files require:
1. Recompiling the Go binary
2. Rebuilding the Docker image with the new binary
3. Restarting the container with the updated image

## Validation Checklist

After applying the fix, verify:

- [ ] Backend container rebuilt successfully
- [ ] Backend container is running (`docker-compose ps`)
- [ ] Backend logs show no errors (`docker-compose logs storage-sage-backend`)
- [ ] Health endpoint responds to GET: `curl -sk https://localhost:8443/api/v1/health`
- [ ] Health endpoint responds to HEAD: `curl -sk -I https://localhost:8443/api/v1/health`
- [ ] All three security headers present in HEAD response
- [ ] Test W15 passes in comprehensive test suite
- [ ] Test script `./test_security_headers.sh` passes

## Security Impact

This fix addresses **HIGH PRIORITY** security issues:

1. ✅ **Prevents MIME-type sniffing attacks** (X-Content-Type-Options)
2. ✅ **Prevents clickjacking attacks** (X-Frame-Options)
3. ✅ **Enforces HTTPS connections** (Strict-Transport-Security)

These headers are required for:
- PCI DSS compliance
- OWASP best practices
- Security audit requirements
- Production deployment standards

## Additional Notes

### Production Deployment
When deploying to production:
1. Rebuild the backend image
2. Push to your container registry
3. Update Kubernetes/ECS/other orchestration with new image
4. Verify headers in production with same tests
5. Run security scanner to confirm vulnerability is resolved

### CI/CD Integration
Add this test to your CI/CD pipeline:
```yaml
# Example GitHub Actions step
- name: Test Security Headers
  run: ./test_security_headers.sh
```

### Monitoring
Consider adding header monitoring:
- Regular security header scans
- Automated tests in CI/CD
- Production monitoring for missing headers
- Security audit compliance checks

## Support

If you encounter issues:
1. Check `docker-compose logs storage-sage-backend`
2. Verify Go version matches Dockerfile requirements
3. Ensure no conflicting middleware is removing headers
4. Review `SECURITY_HEADERS_FIX.md` for technical details

## Related Documentation

- `SECURITY_HEADERS_FIX.md` - Technical details of the fix
- `test_security_headers.sh` - Automated test script
- `scripts/comprehensive_test.sh` - Full test suite
