# StorageSage Secure Quick Start

Get StorageSage running securely in 5 minutes.

## Prerequisites

- Docker & Docker Compose v2+
- OpenSSL (for generating secrets)
- Git (to clone repository)

## Step 1: Clone and Setup (1 minute)

```bash
# Clone repository
git clone https://github.com/your-org/storage-sage.git
cd storage-sage

# Generate secure JWT secret
openssl rand -base64 32 > secrets/jwt_secret.txt

# Verify secret was created
cat secrets/jwt_secret.txt
```

## Step 2: Configure (2 minutes)

```bash
# Copy example config
cp .env.example .env

# Edit configuration (optional)
nano .env
# Review and adjust:
# - BACKEND_PORT (default: 8443)
# - JWT_EXPIRY (default: 24h)
# - TZ (timezone)

# Configure daemon settings
nano web/config/config.yaml
# Adjust:
# - scan_paths (directories to clean)
# - age_threshold_days (default: 7)
# - cleanup_interval_minutes (default: 60)
```

## Step 3: Build and Start (2 minutes)

```bash
# Build all containers
docker compose build

# Start services in background
docker compose up -d

# Verify all services are running
docker compose ps
# Expected: All services "Up" and "healthy"

# Check logs for any errors
docker compose logs --tail=50
```

## Step 4: Verify Security (30 seconds)

```bash
# 1. Verify JWT secret loaded from file
docker compose logs storage-sage-backend | grep "JWT secret"
# Expected: "Loaded JWT secret from file (Docker secrets)"

# 2. Verify non-root execution
docker compose exec storage-sage-daemon id
# Expected: uid=1000 gid=1000

# 3. Test authentication
curl -k -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
# Expected: JSON with token
```

## Step 5: Access Web UI (30 seconds)

```bash
# Open web UI in browser
# https://localhost:8443

# Login with default credentials:
# Username: admin
# Password: admin123

# ⚠️ IMPORTANT: Change default password immediately!
```

## Post-Deployment Security Checklist

### Immediate (Do Now)

- [ ] Change default admin password
- [ ] Review and customize `web/config/config.yaml`
- [ ] Test cleanup on non-production data first
- [ ] Verify scan_paths are correct

### Within 24 Hours

- [ ] Replace self-signed TLS certificates with CA-signed certs
  ```bash
  # Place certificates in web/certs/
  cp your-cert.crt web/certs/server.crt
  cp your-key.key web/certs/server.key
  docker compose restart storage-sage-backend
  ```

- [ ] Set up firewall rules
  ```bash
  # Allow only necessary ports
  sudo firewall-cmd --permanent --add-port=8443/tcp
  sudo firewall-cmd --permanent --add-port=9090/tcp
  sudo firewall-cmd --reload
  ```

- [ ] Configure monitoring/alerting in Grafana
  ```bash
  # Access Grafana (if enabled)
  docker compose --profile grafana up -d
  # Visit http://localhost:3001
  ```

### Within 1 Week

- [ ] Review security documentation: `docs/SECURITY.md`
- [ ] Set up automated backups of SQLite database
- [ ] Configure log rotation
- [ ] Document incident response procedures
- [ ] Schedule regular security audits

## Quick Commands Reference

### Service Management

```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# Restart service
docker compose restart storage-sage-daemon

# View logs
docker compose logs -f storage-sage-daemon
docker compose logs -f storage-sage-backend

# Update and rebuild
git pull
docker compose build
docker compose up -d
```

### Monitoring

```bash
# Check daemon metrics
curl http://localhost:9090/metrics

# Query database
docker compose exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT COUNT(*) FROM deletions;"

# View recent deletions
docker compose exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT datetime(timestamp, 'localtime'), action, path FROM deletions ORDER BY timestamp DESC LIMIT 10;"
```

### Troubleshooting

```bash
# Check service health
docker compose ps
curl -k https://localhost:8443/api/v1/health

# Restart all services
docker compose restart

# View full logs
docker compose logs --tail=100

# Test cleanup manually
docker compose exec storage-sage-daemon pkill -SIGUSR1 storage-sage

# Rebuild from scratch
docker compose down -v
docker compose build --no-cache
docker compose up -d
```

## Testing Your Deployment

```bash
# Run comprehensive test suite
./scripts/test-active-server.sh

# Expected: >90% test pass rate
# Expected: Files being deleted based on age threshold

# Run validation tests
./scripts/validate-all.sh
# (Create this script from VALIDATION_GUIDE.md)
```

## Production Deployment (SystemD)

For production deployment without Docker:

```bash
# 1. Build binary
go build -o storage-sage cmd/storage-sage/main.go

# 2. Install and configure
sudo ./scripts/setup-systemd-user.sh
sudo cp storage-sage /usr/local/bin/
sudo cp web/config/config.yaml /etc/storage-sage/

# 3. Enable and start service
sudo systemctl enable storage-sage
sudo systemctl start storage-sage

# 4. Check status
sudo systemctl status storage-sage
sudo journalctl -u storage-sage -f
```

## Getting Help

- **Documentation:** `docs/` directory
- **Security:** `docs/SECURITY.md`
- **Validation:** `VALIDATION_GUIDE.md`
- **Issues:** GitHub Issues
- **Logs:** `docker compose logs -f`

## Common Issues

### "Cannot connect to backend"
- Check if services are running: `docker compose ps`
- Check firewall: `sudo firewall-cmd --list-ports`
- Check logs: `docker compose logs storage-sage-backend`

### "Authentication failed"
- Verify JWT secret exists: `cat secrets/jwt_secret.txt`
- Check backend logs: `docker compose logs storage-sage-backend | grep JWT`
- Try default credentials: admin/admin123

### "Files not being deleted"
- Verify scan_paths in config: `cat web/config/config.yaml`
- Check file ages: Files must be older than age_threshold_days
- Manually trigger cleanup: `docker compose exec storage-sage-daemon pkill -SIGUSR1 storage-sage`
- Check logs: `docker compose logs storage-sage-daemon`

## Next Steps

1. **Configure cleanup policies** in `web/config/config.yaml`
2. **Set up monitoring** with Grafana dashboards
3. **Review audit logs** regularly
4. **Test thoroughly** on non-production data
5. **Read security documentation** in `docs/SECURITY.md`

---

**You're all set! StorageSage is now running securely with:**
✅ Docker secrets for JWT credentials
✅ Rate limiting on all API endpoints
✅ Non-root container execution
✅ Input size limits
✅ Comprehensive security hardening

Enjoy automated, secure disk cleanup!
