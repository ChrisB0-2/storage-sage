# StorageSage Docker Deployment Guide

Complete containerization setup for StorageSage with production-grade monitoring and security.

## Quick Start

```bash
# 1. Setup environment
make setup

# 2. Edit .env file with your configuration
nano .env

# 3. Build and start
make build
make up

# 4. Verify health
make health
```

**Access Points:**
- Frontend: http://localhost:3000 (if running standalone) or https://localhost:8443 (served by backend)
- Backend API: https://localhost:8443
- Prometheus: http://localhost:9091
- Grafana: http://localhost:3001 (if enabled with `--profile grafana`)

## Architecture

```
┌─────────────────┐
│   Frontend      │  Port 3000 (nginx, optional standalone)
│   (React)       │  OR served by Backend on 8443
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Backend       │  Port 8443 (HTTPS)
│   (Go API)      │
└────────┬────────┘
         │
         ├─────────────────┐
         ▼                 ▼
┌─────────────────┐  ┌──────────────┐
│   Daemon        │  │  Prometheus  │  Port 9091
│   (Cleanup)     │  │  (Metrics)   │
│   Port 9090     │  └──────────────┘
└─────────────────┘         │
                            ▼
                    ┌──────────────┐
                    │   Grafana    │  Port 3001 (optional)
                    │ (Optional)   │
                    └──────────────┘
```

## Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- 2GB+ RAM
- 10GB+ disk space
- OpenSSL (for certificate generation)

## Configuration

### 1. Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
nano .env
```

**Critical Settings:**
- `JWT_SECRET`: Generate with `make secret` or `openssl rand -base64 32`
- `GRAFANA_PASSWORD`: Set a strong password (if using Grafana)
- `NFS_MOUNT_PATH`: Path to your NFS mount on host
- `PROMETHEUS_URL`: URL to fetch metrics from (default: `http://storage-sage-daemon:9090`)

### 2. TLS Certificates

Self-signed certificates are generated automatically with `make setup`. For production:

```bash
# Replace with your CA-signed certificates
cp /path/to/cert.pem web/certs/server.crt
cp /path/to/key.pem web/certs/server.key
```

### 3. NFS Mounts

Configure NFS paths in `docker-compose.yml` volumes section:

```yaml
volumes:
  - /host/nfs/path:/data:ro  # Read-only mount
  - /var/log:/var/log:rw     # Read-write for logs
```

**Important:** Ensure NFS is mounted on the host before starting containers.

### 4. Prometheus Configuration

Edit `prometheus/prometheus.yml` to customize scrape intervals and targets.

### 5. Daemon Configuration

Create `web/config/config.yaml` with your cleanup rules:

```yaml
scan_paths:
  - "/data"
  - "/var/log"
age_off_days: 7
min_free_percent: 10
interval_minutes: 15
prometheus:
  port: 9090
```

## Deployment

### Development

```bash
# Start all services
make up

# View logs
make logs

# Check health
make health
```

### Production

1. **Security Hardening:**
   ```bash
   # Generate secure secrets
   export JWT_SECRET=$(openssl rand -base64 32)
   export GRAFANA_PASSWORD=$(openssl rand -base64 24)
   
   # Update .env
   nano .env
   ```

2. **Build Images:**
   ```bash
   make build
   ```

3. **Start Services:**
   ```bash
   docker-compose up -d
   ```

4. **Verify:**
   ```bash
   make health
   make test
   ```

### Optional Services

**Start Grafana:**
```bash
docker-compose --profile grafana up -d grafana
```

**Start Frontend as Standalone:**
```bash
docker-compose --profile frontend-standalone up -d storage-sage-frontend
```

## Service Management

### Start/Stop

```bash
# Start
make up
# or
docker-compose up -d

# Stop
make down
# or
docker-compose down
```

### Restart

```bash
make restart
# or
docker-compose restart
```

### View Logs

```bash
# All services
make logs

# Specific service
make logs-backend
make logs-daemon
make logs-prometheus
make logs-frontend
```

### Rebuild

```bash
# Rebuild all
make rebuild

# Rebuild specific service
make backend
make frontend
make daemon
```

## Health Checks

All services include health checks:

- **Backend**: `https://localhost:8443/api/v1/health`
- **Daemon**: `http://localhost:9090/metrics`
- **Prometheus**: `http://localhost:9091/-/healthy`
- **Frontend**: `http://localhost:3000/` (if standalone)

Check status:
```bash
make health
docker-compose ps
```

## Troubleshooting

### Services Won't Start

1. **Check logs:**
   ```bash
   docker-compose logs
   ```

2. **Verify ports:**
   ```bash
   # Check if ports are in use
   sudo lsof -i :8443
   sudo lsof -i :9090
   sudo lsof -i :9091
   ```

3. **Check volumes:**
   ```bash
   docker-compose config
   ```

4. **Verify environment:**
   ```bash
   make verify
   ```

### Backend Can't Connect to Prometheus/Daemon

1. **Verify network:**
   ```bash
   docker network inspect storage-sage-network
   ```

2. **Check Prometheus URL in .env:**
   ```bash
   # Should be one of:
   # http://storage-sage-daemon:9090 (daemon metrics)
   # http://prometheus:9090 (Prometheus server)
   grep PROMETHEUS_URL .env
   ```

3. **Test connectivity:**
   ```bash
   docker exec storage-sage-backend wget -O- http://storage-sage-daemon:9090/metrics
   docker exec storage-sage-backend wget -O- http://prometheus:9090/-/healthy
   ```

### NFS Mount Issues

1. **Verify host mount:**
   ```bash
   mount | grep nfs
   ```

2. **Check permissions:**
   ```bash
   ls -la /path/to/nfs
   ```

3. **Test in container:**
   ```bash
   docker exec storage-sage-daemon ls -la /data
   ```

4. **Check volume mounts in docker-compose.yml:**
   ```bash
   docker-compose config | grep -A 5 volumes
   ```

### Certificate Errors

1. **Regenerate certificates:**
   ```bash
   rm web/certs/server.*
   make setup
   ```

2. **For production, use CA-signed certs:**
   ```bash
   cp /path/to/cert.pem web/certs/server.crt
   cp /path/to/key.pem web/certs/server.key
   chmod 644 web/certs/server.crt
   chmod 600 web/certs/server.key
   ```

### Frontend Not Loading

1. **Check if frontend is built:**
   ```bash
   ls -la web/frontend/dist/
   ls -la web/frontend/build/
   ```

2. **Rebuild frontend:**
   ```bash
   cd web/frontend
   npm run build
   ```

3. **Check backend logs:**
   ```bash
   make logs-backend
   ```

### High Memory Usage

1. **Check resource usage:**
   ```bash
   docker stats
   ```

2. **Adjust limits in docker-compose.yml:**
   ```yaml
   services:
     storage-sage-daemon:
       deploy:
         resources:
           limits:
             memory: 512M
   ```

## Security Best Practices

1. **Secrets Management:**
   - Never commit `.env` to version control
   - Use Docker secrets in production
   - Rotate JWT secrets regularly
   - Generate secrets with `make secret`

2. **Network Security:**
   - Use internal Docker networks (already configured)
   - Expose only necessary ports
   - Use reverse proxy (nginx/traefik) in production
   - Enable firewall rules on host

3. **Container Security:**
   - All containers run as non-root users
   - Security options enabled (`no-new-privileges`)
   - Read-only filesystems where possible
   - Minimal base images (Alpine)

4. **TLS:**
   - Use CA-signed certificates in production
   - Enable TLS 1.3 only (already configured)
   - Regular certificate rotation

5. **Image Security:**
   - Scan images for CVEs:
     ```bash
     docker scan storage-sage:backend-latest
     docker scan storage-sage:daemon-latest
     ```

## Monitoring

### Prometheus Metrics

Access Prometheus UI: http://localhost:9091

Key metrics:
- `storagesage_files_deleted_total`
- `storagesage_bytes_freed_total`
- `storagesage_errors_total`
- `storagesage_cleanup_duration_seconds`

### Grafana Dashboards

Access Grafana: http://localhost:3001

Default credentials (change in `.env`):
- Username: `admin`
- Password: (set in `.env`)

To create dashboards:
1. Add Prometheus data source: `http://prometheus:9090`
2. Import dashboard or create custom queries

## Backup & Recovery

### Backup Volumes

```bash
# Backup Prometheus data
docker run --rm -v storage-sage-prometheus-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/prometheus-backup-$(date +%Y%m%d).tar.gz -C /data .

# Backup Grafana data
docker run --rm -v storage-sage-grafana-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/grafana-backup-$(date +%Y%m%d).tar.gz -C /data .

# Backup logs
docker run --rm -v storage-sage-logs:/data -v $(pwd):/backup \
  alpine tar czf /backup/logs-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Restore

```bash
# Restore Prometheus
docker run --rm -v storage-sage-prometheus-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/prometheus-backup-YYYYMMDD.tar.gz -C /data

# Restore Grafana
docker run --rm -v storage-sage-grafana-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/grafana-backup-YYYYMMDD.tar.gz -C /data
```

## Maintenance

### Update Images

```bash
# Pull latest base images
docker-compose pull

# Rebuild
make rebuild
```

### Clean Up

```bash
# Remove stopped containers and unused images
docker system prune

# Full cleanup (removes volumes - data loss!)
make clean
```

### Log Rotation

Logs are stored in Docker volumes. To rotate:

```bash
# View log sizes
docker system df -v

# Clean old logs (if needed)
docker volume prune
```

## Hybrid Deployment

To maintain systemd service capability while using Docker:

1. **Keep systemd service for daemon:**
   ```bash
   # Don't start daemon container
   docker-compose up -d storage-sage-backend prometheus
   ```

2. **Run daemon as systemd service:**
   ```bash
   sudo systemctl start storage-sage
   ```

3. **Update Prometheus config:**
   ```yaml
   scrape_configs:
     - job_name: 'storage-sage-daemon'
       static_configs:
         - targets: ['host.docker.internal:9090']
   ```

4. **Update backend PROMETHEUS_URL:**
   ```bash
   # In .env
   PROMETHEUS_URL=http://host.docker.internal:9090
   ```

## Production Checklist

- [ ] Generate secure JWT secret (`make secret`)
- [ ] Set strong Grafana password
- [ ] Configure CA-signed TLS certificates
- [ ] Set up NFS mounts correctly
- [ ] Configure firewall rules
- [ ] Set up log rotation
- [ ] Configure backup strategy
- [ ] Enable monitoring alerts
- [ ] Review security settings
- [ ] Test disaster recovery
- [ ] Scan images for CVEs
- [ ] Document custom configurations

## Support

For issues:
1. Check logs: `make logs`
2. Verify health: `make health`
3. Review configuration: `docker-compose config`
4. Check documentation: See main README.md

## Quick Reference

```bash
# Setup
make setup

# Build
make build

# Start
make up

# Stop
make down

# Logs
make logs

# Health
make health

# Test
make test

# Clean
make clean

# Rebuild
make rebuild
```

