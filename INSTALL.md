# StorageSage Installation Guide

This guide provides detailed instructions for installing StorageSage in various environments.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation Methods](#installation-methods)
3. [Docker Installation](#docker-installation)
4. [Binary Installation](#binary-installation)
5. [Building from Source](#building-from-source)
6. [Systemd Installation](#systemd-installation)
7. [Kubernetes Installation](#kubernetes-installation)
8. [Post-Installation Setup](#post-installation-setup)

## System Requirements

### Minimum Requirements
- **OS**: Linux (Ubuntu 20.04+, RHEL 8+, Debian 11+, Alpine 3.16+)
- **CPU**: 1 core
- **RAM**: 256 MB
- **Disk**: 100 MB for binaries, additional space for logs and database

### Recommended Requirements
- **CPU**: 2 cores
- **RAM**: 512 MB
- **Disk**: 1 GB

### Dependencies
- **Required**: None (static binaries)
- **Optional**: 
  - Docker 20.10+ (for containerized deployment)
  - Kubernetes 1.21+ (for K8s deployment)
  - Prometheus (for metrics collection)
  - Grafana (for visualization)

## Installation Methods

### Quick Decision Matrix

| Method | Best For | Complexity | Production Ready |
|--------|----------|------------|------------------|
| Docker Compose | Quick start, testing | Low | Yes |
| Pre-built Binary | Traditional servers | Low | Yes |
| Systemd Service | Native Linux deployment | Medium | Yes |
| Kubernetes | Container orchestration | High | Yes |
| Build from Source | Development, customization | Medium | Yes |

## Docker Installation

### Prerequisites
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Method 1: Using Make (Recommended)

```bash
# Clone repository
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Initial setup (creates .env, certificates, config)
make setup

# Generate and set JWT secret
JWT_SECRET=$(make secret)
echo "JWT_SECRET=$JWT_SECRET" >> .env

# Build and start services
make start

# Verify installation
make health
```

### Method 2: Manual Docker Compose

```bash
# Clone repository
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Create .env file
cat > .env << 'EOF'
JWT_SECRET=your-secure-random-secret-here
BACKEND_PORT=8443
DAEMON_METRICS_PORT=9090
EOF

# Generate TLS certificates
mkdir -p web/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout web/certs/server.key \
  -out web/certs/server.crt \
  -subj "/CN=localhost"

# Create configuration
mkdir -p web/config
cp web/config/config.yaml.example web/config/config.yaml

# Edit configuration as needed
vim web/config/config.yaml

# Start services
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs -f
```

### Docker Compose Configuration

The default `docker-compose.yml` includes:
- **storage-sage-daemon**: Cleanup daemon with Prometheus metrics
- **storage-sage-web**: Web UI and API server
- **Volumes**: Persistent storage for database and logs
- **Networks**: Isolated network for service communication

## Binary Installation

### Download Pre-built Binaries

```bash
# Set version
VERSION=v1.0.0  # Replace with latest version

# Linux AMD64
wget https://github.com/ChrisB0-2/storage-sage/releases/download/${VERSION}/storage-sage-linux-amd64.tar.gz
tar xzf storage-sage-linux-amd64.tar.gz

# Linux ARM64
wget https://github.com/ChrisB0-2/storage-sage/releases/download/${VERSION}/storage-sage-linux-arm64.tar.gz
tar xzf storage-sage-linux-arm64.tar.gz

# Install binaries
sudo mv storage-sage /usr/local/bin/
sudo mv storage-sage-query /usr/local/bin/
sudo chmod +x /usr/local/bin/storage-sage*

# Verify installation
storage-sage --version
```

### Create Directories

```bash
# Create configuration directory
sudo mkdir -p /etc/storage-sage

# Create data directories
sudo mkdir -p /var/lib/storage-sage
sudo mkdir -p /var/log/storage-sage

# Create user and set permissions
sudo useradd -r -s /bin/false storagesage
sudo chown -R storagesage:storagesage /var/lib/storage-sage /var/log/storage-sage
```

### Create Configuration

```bash
sudo cat > /etc/storage-sage/config.yaml << 'EOF'
scan_paths:
  - "/tmp/cleanup"
  - "/var/log/old"

age_off_days: 30
min_free_percent: 10
interval_minutes: 60

prometheus:
  port: 9090

database_path: "/var/lib/storage-sage/deletions.db"

logging:
  file_path: "/var/log/storage-sage/cleanup.log"
  max_size_mb: 100
  max_age_days: 30
  max_backups: 5
EOF

sudo chmod 644 /etc/storage-sage/config.yaml
```

### Test Installation

```bash
# Test in dry-run mode
sudo -u storagesage storage-sage \
  --config /etc/storage-sage/config.yaml \
  --dry-run \
  --once

# Check metrics endpoint
curl http://localhost:9090/metrics
```

## Building from Source

### Prerequisites

```bash
# Install Go 1.23 or later
wget https://go.dev/dl/go1.24.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Verify Go installation
go version
```

### Clone and Build

```bash
# Clone repository
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Build daemon
CGO_ENABLED=1 go build -o storage-sage ./cmd/storage-sage

# Build query tool
CGO_ENABLED=1 go build -o storage-sage-query ./cmd/storage-sage-query

# Build web backend (optional)
cd web/backend
go build -o storage-sage-web .

# Install binaries
sudo cp storage-sage /usr/local/bin/
sudo cp storage-sage-query /usr/local/bin/
sudo chmod +x /usr/local/bin/storage-sage*
```

### Build with Custom Flags

```bash
# Build with version information
VERSION=$(git describe --tags --always --dirty)
COMMIT=$(git rev-parse HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

go build \
  -ldflags "-X main.version=${VERSION} -X main.gitCommit=${COMMIT} -X main.buildDate=${BUILD_DATE}" \
  -o storage-sage \
  ./cmd/storage-sage
```

## Systemd Installation

### Create Service File

```bash
sudo cat > /etc/systemd/system/storage-sage.service << 'EOF'
[Unit]
Description=StorageSage Filesystem Cleanup Daemon
Documentation=https://github.com/ChrisB0-2/storage-sage
After=network.target

[Service]
Type=simple
User=storagesage
Group=storagesage
ExecStart=/usr/local/bin/storage-sage --config /etc/storage-sage/config.yaml
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=storage-sage

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/storage-sage /var/log/storage-sage /tmp/cleanup
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF
```

### Enable and Start Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable storage-sage

# Start service
sudo systemctl start storage-sage

# Check status
sudo systemctl status storage-sage

# View logs
sudo journalctl -u storage-sage -f
```

### Service Management

```bash
# Start service
sudo systemctl start storage-sage

# Stop service
sudo systemctl stop storage-sage

# Restart service
sudo systemctl restart storage-sage

# Reload configuration
sudo systemctl reload storage-sage
# OR
sudo kill -HUP $(systemctl show -p MainPID storage-sage | cut -d= -f2)

# Trigger manual cleanup
sudo kill -USR1 $(systemctl show -p MainPID storage-sage | cut -d= -f2)

# View status
sudo systemctl status storage-sage

# View logs
sudo journalctl -u storage-sage -n 100
sudo journalctl -u storage-sage --since "1 hour ago"
```

## Kubernetes Installation

### Using Kubectl

```bash
# Create namespace
kubectl create namespace storage-sage

# Create ConfigMap
kubectl create configmap storage-sage-config \
  --from-file=config.yaml=/etc/storage-sage/config.yaml \
  -n storage-sage

# Create Secret
kubectl create secret generic storage-sage-jwt \
  --from-literal=jwt-secret=$(openssl rand -base64 32) \
  -n storage-sage

# Apply manifests
kubectl apply -f docs/kubernetes/deployment.yaml
kubectl apply -f docs/kubernetes/service.yaml

# Check status
kubectl get pods -n storage-sage
kubectl logs -f deployment/storage-sage-daemon -n storage-sage
```

### Using Helm

```bash
# Add Helm repository (when available)
helm repo add storage-sage https://YOUR_GITHUB_USERNAME.github.io/storage-sage
helm repo update

# Install with default values
helm install storage-sage storage-sage/storage-sage -n storage-sage --create-namespace

# Install with custom values
cat > values.yaml << 'EOF'
config:
  scan_paths:
    - "/var/log"
  age_off_days: 30
  interval_minutes: 60

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

persistence:
  enabled: true
  size: 10Gi
EOF

helm install storage-sage storage-sage/storage-sage \
  -n storage-sage \
  --create-namespace \
  -f values.yaml

# Verify installation
helm status storage-sage -n storage-sage
kubectl get all -n storage-sage
```

## Post-Installation Setup

### 1. Configure Monitoring

```bash
# Add Prometheus scrape config
cat >> /etc/prometheus/prometheus.yml << 'EOF'
scrape_configs:
  - job_name: 'storage-sage'
    static_configs:
      - targets: ['localhost:9090']
EOF

# Reload Prometheus
sudo systemctl reload prometheus
```

### 2. Import Grafana Dashboard

```bash
# Copy dashboard JSON
sudo cp storage_sage_dashboard.json /var/lib/grafana/dashboards/

# Or import via UI:
# Grafana -> Dashboards -> Import -> Upload JSON file
```

### 3. Configure Log Rotation

```bash
# Create logrotate config
sudo cat > /etc/logrotate.d/storage-sage << 'EOF'
/var/log/storage-sage/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    missingok
    copytruncate
}
EOF
```

### 4. Set Up Backup

```bash
# Backup database
#!/bin/bash
BACKUP_DIR="/var/backups/storage-sage"
mkdir -p $BACKUP_DIR
cp /var/lib/storage-sage/deletions.db $BACKUP_DIR/deletions-$(date +%Y%m%d).db
find $BACKUP_DIR -name "deletions-*.db" -mtime +30 -delete
```

### 5. Configure Firewall

```bash
# Open Prometheus metrics port
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --reload

# Or with iptables
sudo iptables -A INPUT -p tcp --dport 9090 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4
```

## Verification

### Health Checks

```bash
# Check daemon is running
ps aux | grep storage-sage

# Check metrics endpoint
curl http://localhost:9090/metrics | grep storagesage

# Check database
storage-sage-query --stats

# Check logs
tail -f /var/log/storage-sage/cleanup.log
```

### Test Cleanup

```bash
# Create test files
mkdir -p /tmp/cleanup-test
touch -d "40 days ago" /tmp/cleanup-test/old-file.txt
touch /tmp/cleanup-test/new-file.txt

# Run dry-run
storage-sage --config /etc/storage-sage/config.yaml --dry-run --once

# Check output
# Should indicate old-file.txt would be deleted, new-file.txt kept
```

## Troubleshooting Installation

### Common Issues

#### Permission Denied
```bash
# Fix permissions
sudo chown -R storagesage:storagesage /var/lib/storage-sage /var/log/storage-sage
sudo chmod 755 /var/lib/storage-sage /var/log/storage-sage
```

#### Port Already in Use
```bash
# Check what's using port 9090
sudo lsof -i :9090
sudo netstat -tulpn | grep 9090

# Change port in config.yaml
prometheus:
  port: 9091
```

#### Database Lock Error
```bash
# Stop duplicate instances
sudo systemctl stop storage-sage
pkill storage-sage

# Check for stale locks
ls -la /var/lib/storage-sage/

# Restart
sudo systemctl start storage-sage
```

#### Build Errors
```bash
# CGO required for SQLite
CGO_ENABLED=1 go build ./cmd/storage-sage

# Install build dependencies (Alpine)
apk add --no-cache gcc musl-dev sqlite-dev

# Install build dependencies (Ubuntu/Debian)
apt-get install -y build-essential libsqlite3-dev
```

## Uninstallation

### Docker
```bash
make down
docker-compose down -v
rm -rf web/certs web/config .env
```

### Binary/Systemd
```bash
# Stop and disable service
sudo systemctl stop storage-sage
sudo systemctl disable storage-sage
sudo rm /etc/systemd/system/storage-sage.service
sudo systemctl daemon-reload

# Remove binaries
sudo rm /usr/local/bin/storage-sage*

# Remove data (optional)
sudo rm -rf /etc/storage-sage
sudo rm -rf /var/lib/storage-sage
sudo rm -rf /var/log/storage-sage

# Remove user
sudo userdel storagesage
```

### Kubernetes
```bash
helm uninstall storage-sage -n storage-sage
kubectl delete namespace storage-sage
```

## Next Steps

After installation:

1. Review [Configuration Guide](docs/configuration.md)
2. Set up [Monitoring](docs/monitoring.md)
3. Configure [Alerting](docs/alerting.md)
4. Read [Operations Guide](docs/operations.md)
5. Join community discussions

## Support

For installation issues:
- Check [Troubleshooting Guide](docs/troubleshooting.md)
- Search [GitHub Issues](https://github.com/ChrisB0-2/storage-sage/issues)
- Ask in [Discussions](https://github.com/ChrisB0-2/storage-sage/discussions)
