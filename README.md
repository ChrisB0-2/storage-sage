# StorageSage

**Intelligent Automated Storage Cleanup for Enterprise Systems**

StorageSage is a production-grade distributed storage management system that automatically cleans up old files based on configurable age and disk usage thresholds. Built for reliability, observability, and scalability.

[![Tests](https://img.shields.io/badge/tests-45%2F45%20passing-success)]()
[![Go Version](https://img.shields.io/badge/go-1.24-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

## Features

### Core Capabilities
- ✅ **Multi-Mode Cleanup** - Age-based, disk-usage-based, and stacked cleanup strategies
- ✅ **Path-Specific Rules** - Configure different retention policies per directory
- ✅ **Priority-Based Deletion** - Control cleanup order with configurable priorities
- ✅ **Real-Time Monitoring** - Prometheus metrics, Grafana dashboards, and Loki log aggregation
- ✅ **RESTful API** - Complete HTTP API for configuration, status, and manual triggers
- ✅ **Web UI** - React-based dashboard for monitoring and management
- ✅ **SQLite History** - Complete audit trail of all deletions with queryable CLI
- ✅ **Production Ready** - TLS encryption, JWT authentication, health checks, and security headers

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        StorageSage System                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐  │
│  │   Daemon     │      │  Web Backend │      │  Web Frontend│  │
│  │   (Go)       │◄────►│   (Go)       │◄────►│   (React)    │  │
│  │              │      │              │      │              │  │
│  │ - Scanning   │      │ - REST API   │      │ - Dashboard  │  │
│  │ - Cleanup    │      │ - Auth (JWT) │      │ - Config UI  │  │
│  │ - Metrics    │      │ - Config Mgmt│      │ - Logs View  │  │
│  └──────┬───────┘      └──────┬───────┘      └──────────────┘  │
│         │                     │                                 │
│         │                     │                                 │
│  ┌──────▼───────────────┬────▼────────┬──────────────────────┐ │
│  │                      │             │                       │ │
│  │  SQLite Database     │  Prometheus │  Loki + Promtail     │ │
│  │  (Deletion History)  │  (Metrics)  │  (Logs)              │ │
│  │                      │             │                       │ │
│  └──────────────────────┴─────────────┴──────────────────────┘ │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Grafana (Visualization)                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Go 1.24+ (for local development)
- 2GB RAM minimum
- Linux, macOS, or Windows with WSL2

### Installation

```bash
# Clone the repository
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Generate TLS certificates for HTTPS
mkdir -p web/certs
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout web/certs/key.pem \
  -out web/certs/cert.pem \
  -days 365 \
  -subj "/CN=localhost"

# Create JWT secret
mkdir -p secrets
openssl rand -base64 32 > secrets/jwt_secret.txt

# Create configuration
cp web/config/config.yaml.example web/config/config.yaml

# Edit configuration (optional)
vim web/config/config.yaml

# Start all services
./scripts/start.sh --mode docker --all
```

### Verify Installation

```bash
# Run comprehensive test suite
./scripts/comprehensive_test.sh

# Expected output: ✅ ALL TESTS PASSED (45/45)
```

## Access Points

After starting the system:

| Service | URL | Description |
|---------|-----|-------------|
| **Web UI** | https://localhost:8443 | Main dashboard and management interface |
| **Backend API** | https://localhost:8443/api/v1 | REST API endpoints |
| **Daemon Metrics** | http://localhost:9090/metrics | Prometheus metrics endpoint |
| **Prometheus** | http://localhost:9091 | Metrics aggregation and queries |
| **Grafana** | http://localhost:3001 | Metrics visualization and dashboards |
| **Loki** | http://localhost:3100 | Log aggregation API |

**Default Credentials:**
- Web UI / API: `admin` / `changeme`
- Grafana: `admin` / `admin`

## Configuration

Edit `/web/config/config.yaml`:

```yaml
# Global defaults
scan_paths:
  - /var/log
  - /data/backups

min_free_percent: 10      # Minimum free space to maintain
age_off_days: 30          # Delete files older than this
interval_minutes: 15      # Cleanup frequency

# Path-specific rules (override global defaults)
paths:
  - path: /data/backups
    age_off_days: 7              # Keep backups for 7 days
    min_free_percent: 5          # Lower threshold for this path
    max_free_percent: 90         # Trigger cleanup at 90% usage
    target_free_percent: 80      # Clean until 80% usage
    priority: 1                  # Higher priority (deleted first)
    stack_threshold: 95          # Emergency cleanup at 95%
    stack_age_days: 14           # Emergency mode: delete files >14 days

  - path: /var/log
    age_off_days: 90
    priority: 2
    max_free_percent: 85
    target_free_percent: 70

# Prometheus metrics
prometheus:
  port: 9090

# Database for deletion history
database_path: /var/lib/storage-sage/deletions.db

# Cleanup behavior
cleanup_options:
  recursive: true           # Scan directories recursively
  delete_dirs: false        # Only delete files, not directories

# Resource limits
resource_limits:
  max_cpu_percent: 10.0     # CPU throttling

# Logging
logging:
  rotation_days: 30         # Keep logs for 30 days
```

## Usage

### Web UI

1. **Login** at https://localhost:8443
2. **Dashboard** - View real-time metrics and cleanup status
3. **Configuration** - Edit cleanup rules and thresholds
4. **Deletions Log** - Browse deletion history
5. **Manual Cleanup** - Trigger cleanup immediately

### API Examples

```bash
# Authenticate
TOKEN=$(curl -sk -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}' \
  | jq -r '.token')

# Get current configuration
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/config | jq

# Trigger manual cleanup
curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/trigger

# Get cleanup status
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/cleanup/status | jq

# View deletion history
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8443/api/v1/deletions/log?limit=10" | jq

# Get current metrics
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/metrics/current
```

### Database Queries

```bash
# Query deletion statistics
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --stats

# View recent deletions
docker exec storage-sage-daemon storage-sage-query \
  --db /var/lib/storage-sage/deletions.db \
  --recent 20

# Direct SQLite queries
docker exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db \
  "SELECT COUNT(*), SUM(size) FROM deletions WHERE mode='AGE'"
```

### Metrics

StorageSage exposes Prometheus metrics at http://localhost:9090/metrics:

**Core Metrics:**
- `storagesage_files_deleted_total` - Total files deleted (counter)
- `storagesage_bytes_freed_total` - Total bytes freed (counter)
- `storagesage_errors_total` - Total errors encountered (counter)
- `storagesage_cleanup_duration_seconds` - Cleanup cycle duration (histogram)

**Spec-Required Metrics:**
- `storage_sage_free_space_percent{path}` - Current free space percentage per path (gauge)
- `storage_sage_cleanup_last_run_timestamp` - Unix timestamp of last cleanup (gauge)
- `storage_sage_cleanup_last_mode{mode}` - Last cleanup mode used (gauge)
- `storage_sage_path_bytes_deleted_total{path}` - Bytes deleted per path (counter)

**Example Queries:**

```promql
# Files deleted per minute
rate(storagesage_files_deleted_total[5m]) * 60

# Total bytes freed
storagesage_bytes_freed_total

# Free space percentage by path
storage_sage_free_space_percent

# Average cleanup duration
rate(storagesage_cleanup_duration_seconds_sum[5m]) / rate(storagesage_cleanup_duration_seconds_count[5m])
```

### Logs

View logs via Loki at http://localhost:3100:

```bash
# All storage-sage logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="storage-sage"}' \
  | jq

# Only deletion logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="storage-sage"} |= "DELETED"' \
  | jq

# Or use Grafana Explore at http://localhost:3001
```

## Cleanup Modes

StorageSage intelligently chooses between three cleanup modes:

### 1. AGE Mode (Default)
- Triggered when: Disk usage below thresholds
- Behavior: Delete files older than `age_off_days`
- Use case: Regular maintenance, predictable cleanup

### 2. DISK-USAGE Mode
- Triggered when: Free space < `max_free_percent`
- Behavior: Delete oldest files until reaching `target_free_percent`
- Use case: Storage approaching capacity

### 3. STACK Mode (Emergency)
- Triggered when: Free space < `stack_threshold` (e.g., 95%)
- Behavior: Aggressively delete files older than `stack_age_days`
- Use case: Critical storage situation, prevents disk full

**Mode Selection Logic:**
```
if free_space < stack_threshold:
    mode = STACK
elif free_space < max_free_percent:
    mode = DISK-USAGE
else:
    mode = AGE
```

## Development

### Build from Source

```bash
# Build daemon
cd cmd/storage-sage
go build -o storage-sage

# Build query tool
cd cmd/storage-sage-query
go build -o storage-sage-query

# Build backend
cd web/backend
go build -o backend

# Build frontend
cd web/frontend
npm install
npm run build
```

### Run Tests

```bash
# Unit tests
go test ./...

# Integration tests
./scripts/comprehensive_test.sh

# Specific test categories
./scripts/comprehensive_test.sh | grep "DAEMON CORE FEATURES" -A 20
```

### Development Mode

```bash
# Run daemon locally
./storage-sage --config /etc/storage-sage/config.yaml

# Run in foreground (debug)
./scripts/start.sh --mode direct --foreground --verbose

# Run once (no loop)
./storage-sage --config /etc/storage-sage/config.yaml --once

# Dry run (no deletions)
./storage-sage --config /etc/storage-sage/config.yaml --dry-run
```

## Deployment

### Docker Compose (Recommended)

```bash
# Production deployment
./scripts/start.sh --mode docker --all

# Daemon only (no UI)
./scripts/start.sh --mode docker

# Check status
./scripts/status.sh

# Stop all services
docker-compose down

# View logs
docker-compose logs -f storage-sage-daemon
docker-compose logs -f storage-sage-backend
```

### Systemd Service

```bash
# Install as system service
sudo cp storage-sage.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable storage-sage
sudo systemctl start storage-sage

# Check status
systemctl status storage-sage
journalctl -u storage-sage -f

# Use start script (auto-detects systemd)
./scripts/start.sh
```

### Environment Variables

```bash
# Override defaults
export DAEMON_METRICS_PORT=9090
export BACKEND_PORT=8443
export GRAFANA_PASSWORD=securepassword
export PROMETHEUS_PORT=9091

# Start with custom settings
./scripts/start.sh --mode docker --all
```

## Monitoring & Alerting

### Grafana Dashboards

Pre-built dashboard "StorageSage Deletion Analytics" includes:
- Files deleted over time
- Bytes freed statistics
- Free space gauges per path
- Cleanup mode distribution
- Top deleted paths
- Recent deletion logs

### Prometheus Alerts (Example)

```yaml
groups:
  - name: storage-sage
    rules:
      - alert: LowDiskSpace
        expr: storage_sage_free_space_percent < 10
        for: 5m
        annotations:
          summary: "Low disk space on {{ $labels.path }}"

      - alert: CleanupFailures
        expr: rate(storagesage_errors_total[5m]) > 0
        for: 2m
        annotations:
          summary: "StorageSage cleanup errors detected"

      - alert: NoRecentCleanup
        expr: time() - storage_sage_cleanup_last_run_timestamp > 3600
        for: 10m
        annotations:
          summary: "No cleanup in last hour"
```

## Troubleshooting

### Common Issues

**1. Container won't start**
```bash
# Check logs
docker logs storage-sage-daemon --tail 50

# Verify config
docker exec storage-sage-daemon cat /etc/storage-sage/config.yaml

# Check permissions
docker exec storage-sage-daemon ls -la /var/lib/storage-sage
```

**2. No files being deleted**
```bash
# Check cleanup mode
curl -s http://localhost:9090/metrics | grep cleanup_last_mode

# Verify file ages
docker exec storage-sage-daemon find /test-workspace -type f -mtime +7 -ls

# Check logs for scan results
docker logs storage-sage-daemon | grep "candidates_found"
```

**3. Metrics not appearing**
```bash
# Verify daemon is running
docker ps | grep storage-sage-daemon

# Test metrics endpoint
curl http://localhost:9090/metrics | grep storage_sage

# Check Prometheus scrape status
curl http://localhost:9091/api/v1/targets
```

**4. Database errors**
```bash
# Check database schema
docker exec storage-sage-daemon sqlite3 /var/lib/storage-sage/deletions.db ".schema"

# Recreate database (WARNING: loses history)
docker volume rm storage-sage-db
docker-compose restart storage-sage-daemon
```

### Debug Mode

```bash
# Enable verbose logging
./scripts/start.sh --mode direct --foreground --verbose

# Check daemon health
curl http://localhost:9090/health | jq

# Verify configuration
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://localhost:8443/api/v1/config/validate \
  -X POST -H "Content-Type: application/json" \
  -d @web/config/config.yaml | jq
```

## Performance

### Resource Usage

Typical footprint (all services):
- CPU: 2-5% (idle), 10-20% (during cleanup)
- Memory: ~500MB total
- Disk: ~100MB (binaries + containers)
- Network: Minimal (local only)

### Scaling Recommendations

- **Small deployments** (< 1TB): Default settings work well
- **Medium deployments** (1-10TB): Increase `interval_minutes` to 30-60
- **Large deployments** (10TB+): Consider multiple daemon instances per path
- **Very large deployments**: Use Kubernetes for horizontal scaling

## Security

### Best Practices

1. **Change default passwords** immediately
2. **Use strong JWT secrets**: `openssl rand -base64 64 > secrets/jwt_secret.txt`
3. **Restrict network access**: Bind to localhost or use firewall rules
4. **Enable TLS**: Always use HTTPS in production
5. **Rotate credentials**: Implement periodic password rotation
6. **Audit logs**: Review deletion logs regularly
7. **Backup database**: Regular backups of deletion history

### Security Features

- ✅ TLS 1.2+ encryption for all API traffic
- ✅ JWT-based authentication with configurable expiry
- ✅ Security headers (X-Frame-Options, X-Content-Type-Options, HSTS)
- ✅ Non-root container execution
- ✅ Read-only root filesystem option
- ✅ No privilege escalation
- ✅ Secret management via Docker secrets

## Contributing

We welcome contributions! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for new functionality
4. Ensure all tests pass (`./scripts/comprehensive_test.sh`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Guidelines

- Follow Go best practices and `gofmt` formatting
- Add tests for all new features
- Update documentation for API changes
- Maintain backward compatibility when possible
- Write descriptive commit messages

## License

MIT License - see [LICENSE](LICENSE) file for details

## Support

- **Documentation**: See `/docs` directory
- **Issues**: https://github.com/ChrisB0-2/storage-sage/issues
- **Discussions**: https://github.com/ChrisB0-2/storage-sage/discussions

## Acknowledgments

Built with:
- [Go](https://golang.org/) - Daemon and backend
- [React](https://reactjs.org/) - Frontend UI
- [Prometheus](https://prometheus.io/) - Metrics collection
- [Grafana](https://grafana.com/) - Visualization
- [Loki](https://grafana.com/oss/loki/) - Log aggregation
- [Docker](https://www.docker.com/) - Containerization

---

**StorageSage** - Intelligent storage management for modern infrastructure.

Made with ❤️ for system administrators everywhere.
