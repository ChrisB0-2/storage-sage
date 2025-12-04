# StorageSage Manual Deployment Guide

**Environment:** Docker Compose
**Last Updated:** 2025-11-20
**Status:** Ready for deployment - All prerequisites exist

## Quick Status Check

All required files are already in place:
- ✅ TLS Certificates: `web/certs/server.crt` and `web/certs/server.key`
- ✅ JWT Secret: `secrets/jwt_secret.txt`
- ✅ Configuration: `web/config/config.yaml`
- ✅ Docker Compose: `docker-compose.yml`
- ✅ Environment: `.env`

## Deployment Steps

### Step 1: Verify Prerequisites

```bash
cd /home/user/projects/storage-sage
pwd
# Should output: /home/user/projects/storage-sage

# Verify Docker is available
docker --version
docker compose version

# Check Docker daemon is running
docker ps
```

### Step 2: Review and Update Configuration (Optional)

```bash
# Review current configuration
cat web/config/config.yaml

# Edit if needed
nano web/config/config.yaml
```

**Current Configuration:**
- Scan paths: `/var/log`, `/test-workspace`, `/tmp/storage-sage-test-workspace`
- Age off days: 0 (immediate cleanup)
- Interval: 1 minute
- Min free percent: 10%
- Database: `/var/lib/storage-sage/deletions.db`
- Prometheus port: 9090

### Step 3: Create Test Workspace

```bash
# Create test directory with old files
mkdir -p /tmp/storage-sage-test-workspace
echo "This file is for testing age-based deletion" > /tmp/storage-sage-test-workspace/test-file-old.txt

# Set file timestamp to 2 days ago
touch -d "2 days ago" /tmp/storage-sage-test-workspace/test-file-old.txt

# Verify
ls -la /tmp/storage-sage-test-workspace/
```

### Step 4: Review Environment Variables

```bash
# Check current .env file
cat .env

# If JWT_SECRET is not set, generate one:
# openssl rand -base64 32
```

### Step 5: Build Docker Images

```bash
# Build all images (this may take 10-15 minutes on first build)
docker compose build --no-cache

# Or use Makefile
make build
```

**Expected output:**
- Building storage-sage-daemon image
- Building storage-sage-backend image
- Building storage-sage-frontend image

### Step 6: Start Services

```bash
# Start all services in detached mode
docker compose up -d

# Or use Makefile
make up
```

**Services started:**
- storage-sage-daemon (port 9090)
- storage-sage-backend (port 8443)
- storage-sage-loki (port 3100)
- storage-sage-promtail (port 9080)

### Step 7: Monitor Startup

```bash
# Check container status
docker compose ps

# Follow logs (press Ctrl+C to exit)
docker compose logs -f --tail=50

# Or check individual service logs
docker compose logs storage-sage-daemon
docker compose logs storage-sage-backend
```

**Wait for these messages:**
- Daemon: "StorageSage daemon started"
- Backend: "Server started successfully" or "Listening on :8443"

### Step 8: Health Check (Wait 30 seconds)

```bash
# Wait for services to initialize
sleep 30

# Check daemon health (Prometheus metrics)
curl -s http://localhost:9090/metrics | grep storagesage_

# Check backend health
curl -k https://localhost:8443/api/v1/health

# Check all container health
docker compose ps
```

**Expected outputs:**
- Daemon: Should show multiple `storagesage_*` metrics
- Backend: `{"status":"healthy"}`
- Containers: All should show "(healthy)" status

### Step 9: Run Comprehensive Test Suite

```bash
# Make test script executable
chmod +x scripts/comprehensive_test.sh

# Run tests
./scripts/comprehensive_test.sh
```

**Expected results:**
- Total Tests: 25-30
- Passed: 20-30 (depending on services running)
- Failed: 0
- Skipped: 0-5 (if optional services not running)

### Step 10: Access Web Interface

**Backend API:**
```bash
# Health check
curl -k https://localhost:8443/api/v1/health

# Login (get JWT token)
curl -k -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}'

# Save token
TOKEN="<token-from-above>"

# Get configuration
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/config
```

**Frontend UI:**
- Open browser to: https://localhost:8443
- Login: username `admin`, password `changeme`
- Accept self-signed certificate warning

### Step 11: Verify Daemon Functionality

```bash
# Check metrics endpoint
curl http://localhost:9090/metrics | grep storagesage_

# Query database for deletions
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db --recent 20

# Check database statistics
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db --stats
```

### Step 12: Trigger Manual Cleanup (Optional)

```bash
# Get JWT token first (from Step 10)
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' | jq -r '.token')

# Trigger cleanup
curl -k -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# Check cleanup status
curl -k -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/status

# View deletions log
curl -k -H "Authorization: Bearer $TOKEN" \
  'https://localhost:8443/api/v1/deletions/log?limit=10'
```

## Useful Commands

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f storage-sage-daemon
docker compose logs -f storage-sage-backend

# Last 100 lines
docker compose logs --tail=100
```

### Restart Services

```bash
# Restart all
docker compose restart

# Restart specific service
docker compose restart storage-sage-daemon

# Or use Makefile
make restart
```

### Stop Services

```bash
# Stop all (keeps volumes)
docker compose down

# Stop and remove volumes (CAUTION: deletes data)
docker compose down -v

# Or use Makefile
make down
make clean  # removes volumes
```

### Shell Access

```bash
# Backend shell
docker compose exec storage-sage-backend sh

# Daemon shell
docker compose exec storage-sage-daemon sh
```

## Troubleshooting

### Port Conflicts

If ports are already in use:

```bash
# Check what's using the ports
sudo lsof -i :8443  # Backend
sudo lsof -i :9090  # Daemon metrics

# Change ports in .env file
nano .env
# Update BACKEND_PORT, DAEMON_METRICS_PORT, etc.
```

### Container Won't Start

```bash
# Check logs
docker compose logs <container-name>

# Check container details
docker inspect <container-name>

# Rebuild specific service
docker compose build --no-cache <service-name>
docker compose up -d <service-name>
```

### Authentication Failures

```bash
# Verify JWT secret exists
cat secrets/jwt_secret.txt

# Check backend environment
docker compose exec storage-sage-backend env | grep JWT

# Regenerate JWT secret if needed
openssl rand -base64 32 > secrets/jwt_secret.txt
docker compose restart storage-sage-backend
```

### Database Issues

```bash
# Check database file exists
docker exec storage-sage-daemon ls -la /var/lib/storage-sage/

# Check database permissions
docker exec storage-sage-daemon stat /var/lib/storage-sage/deletions.db

# View database contents
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db --stats
```

### TLS Certificate Issues

```bash
# Regenerate certificates
mkdir -p web/certs
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout web/certs/server.key \
  -out web/certs/server.crt \
  -days 365 \
  -subj "/C=US/ST=State/L=City/O=StorageSage/CN=localhost"

chmod 600 web/certs/server.key
chmod 644 web/certs/server.crt

# Restart backend
docker compose restart storage-sage-backend
```

### Cleanup Not Running

```bash
# Check daemon logs
docker compose logs storage-sage-daemon | tail -50

# Verify configuration
docker exec storage-sage-daemon cat /etc/storage-sage/config.yaml

# Check metrics
curl http://localhost:9090/metrics | grep cleanup

# Trigger manual cleanup
curl -k -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger
```

## Testing Checklist

Use this checklist to verify deployment:

- [ ] Docker daemon is running
- [ ] All containers started successfully
- [ ] Health checks pass for all services
- [ ] Daemon metrics endpoint accessible (http://localhost:9090/metrics)
- [ ] Backend health check passes (https://localhost:8443/api/v1/health)
- [ ] Authentication works (can get JWT token)
- [ ] Can retrieve configuration via API
- [ ] Can trigger manual cleanup
- [ ] Can query database for deletions
- [ ] Frontend UI loads (https://localhost:8443)
- [ ] Comprehensive test suite passes

## Security Notes

### Default Credentials

**IMPORTANT:** Change default credentials before production use!

```bash
# Default backend credentials
Username: admin
Password: changeme
```

To change: Edit `web/backend/auth/jwt.go` or use environment variables if supported.

### TLS Certificates

Current setup uses self-signed certificates for development. For production:

1. Obtain certificates from a Certificate Authority (CA)
2. Replace `web/certs/server.crt` and `web/certs/server.key`
3. Restart backend: `docker compose restart storage-sage-backend`

### JWT Secret

Current JWT secret is stored in `secrets/jwt_secret.txt`. To rotate:

```bash
# Generate new secret
openssl rand -base64 32 > secrets/jwt_secret.txt

# Restart backend
docker compose restart storage-sage-backend
```

Note: This will invalidate all existing tokens.

## Monitoring

### Prometheus Metrics

Access daemon metrics:
```bash
curl http://localhost:9090/metrics
```

Key metrics:
- `storagesage_files_deleted_total` - Total files deleted
- `storagesage_bytes_freed_total` - Total bytes freed
- `storagesage_errors_total` - Total errors encountered
- `storagesage_cleanup_duration_seconds` - Cleanup duration histogram

### Logs via Loki

Logs are collected by Promtail and sent to Loki.

Query logs:
```bash
# Get recent logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="storage-sage"}' \
  | jq '.data.result'
```

### Grafana (Optional)

Start Grafana:
```bash
docker compose --profile grafana up -d
```

Access: http://localhost:3001
- Username: admin
- Password: (set in .env as GRAFANA_PASSWORD)

## Performance Tuning

### Resource Limits

Edit `docker-compose.yml` to adjust resource limits:

```yaml
services:
  storage-sage-daemon:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Cleanup Interval

Edit `web/config/config.yaml`:

```yaml
interval_minutes: 15  # Change from 1 to reduce frequency
```

Restart daemon: `docker compose restart storage-sage-daemon`

## Backup and Recovery

### Backup Database

```bash
# Backup deletions database
docker exec storage-sage-daemon cat /var/lib/storage-sage/deletions.db > \
  backup-deletions-$(date +%Y%m%d).db

# Or copy entire volume
docker run --rm -v storage-sage-db:/data -v $(pwd):/backup \
  alpine tar czf /backup/storage-sage-db-$(date +%Y%m%d).tar.gz /data
```

### Restore Database

```bash
# Stop daemon
docker compose stop storage-sage-daemon

# Restore database
docker run --rm -v storage-sage-db:/data -v $(pwd):/backup \
  alpine tar xzf /backup/storage-sage-db-YYYYMMDD.tar.gz -C /

# Start daemon
docker compose start storage-sage-daemon
```

## Next Steps

1. **Production Setup:**
   - Replace self-signed certificates with CA-signed certificates
   - Change default credentials
   - Set strong JWT secret
   - Configure proper scan paths in `web/config/config.yaml`
   - Set appropriate age thresholds and cleanup intervals

2. **Monitoring Setup:**
   - Configure external Prometheus to scrape metrics
   - Set up alerts for cleanup failures
   - Enable Grafana for visualization

3. **Integrate with Systems:**
   - Mount production NFS shares
   - Configure log rotation
   - Set up automated backups
   - Integrate with SSO/LDAP for authentication

## Support

For issues or questions:
- Check logs: `docker compose logs`
- Run test suite: `./scripts/comprehensive_test.sh`
- Review troubleshooting section above
- Check GitHub issues: https://github.com/your-org/storage-sage/issues
