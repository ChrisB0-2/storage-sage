# Installation Guide

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation Methods](#installation-methods)
  - [Binary Installation](#binary-installation)
  - [Package Manager Installation](#package-manager-installation)
  - [Docker Installation](#docker-installation)
  - [Build from Source](#build-from-source)
- [Configuration](#configuration)
- [Running StorageSage](#running-storagesage)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Uninstallation](#uninstallation)

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+, Debian 11+, RHEL 8+, Rocky Linux 8+, Arch) or macOS 11+
- **Architecture**: AMD64 (x86_64) or ARM64
- **Memory**: Minimum 256MB RAM (512MB recommended)
- **Disk Space**: 100MB for installation, additional space for database and logs
- **Permissions**: Root or sudo access for system-wide installation

### Software Dependencies

For binary/package installation:
- systemd (Linux) for daemon management
- SQLite3 libraries (usually included)

For Docker installation:
- Docker Engine 20.10+ or Docker Desktop
- Docker Compose v2.0+

For building from source:
- Go 1.21 or later
- gcc (for CGO/SQLite)
- make

## Installation Methods

### Binary Installation

Download the latest release for your platform:

#### Linux AMD64

```bash
# Download
VERSION=v1.0.0  # Replace with latest version
wget https://github.com/ChrisB0-2/storage-sage/releases/download/\${VERSION}/storage-sage_\${VERSION}_linux_amd64.tar.gz

# Extract
tar xzf storage-sage_\${VERSION}_linux_amd64.tar.gz

# Install binaries
sudo mv storage-sage storage-sage-query /usr/local/bin/
sudo chmod +x /usr/local/bin/storage-sage*

# Verify installation
storage-sage --version
```

#### macOS

```bash
# Download
VERSION=v1.0.0
wget https://github.com/ChrisB0-2/storage-sage/releases/download/\${VERSION}/storage-sage_\${VERSION}_darwin_amd64.tar.gz

# Extract and install
tar xzf storage-sage_\${VERSION}_darwin_amd64.tar.gz
sudo mv storage-sage storage-sage-query /usr/local/bin/
```

### Package Manager Installation

#### Debian/Ubuntu (.deb)

```bash
VERSION=v1.0.0
wget https://github.com/ChrisB0-2/storage-sage/releases/download/\${VERSION}/storage-sage_\${VERSION}_amd64.deb
sudo dpkg -i storage-sage_\${VERSION}_amd64.deb
```

#### RHEL/Rocky Linux (.rpm)

```bash
VERSION=v1.0.0
wget https://github.com/ChrisB0-2/storage-sage/releases/download/\${VERSION}/storage-sage_\${VERSION}_amd64.rpm
sudo rpm -i storage-sage_\${VERSION}_amd64.rpm
```

### Docker Installation

```bash
# Clone repository
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Configure environment
cp .env.example .env
nano .env

# Generate secrets
openssl rand -base64 32 > secrets/jwt_secret.txt

# Generate TLS certificates
make setup

# Start services
docker compose up -d
```

### Build from Source

```bash
# Clone repository
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Build
go mod download
make build

# Install (optional)
sudo make install
```

## Configuration

### Create Directories

```bash
sudo mkdir -p /etc/storage-sage
sudo mkdir -p /var/lib/storage-sage
sudo mkdir -p /var/log/storage-sage
```

### Copy Configuration

```bash
sudo cp test-config.yaml /etc/storage-sage/config.yaml
sudo nano /etc/storage-sage/config.yaml
```

### Configure Environment (Docker/Web)

```bash
cp .env.example .env
openssl rand -base64 32 > secrets/jwt_secret.txt
nano .env
```

## Running StorageSage

### Systemd Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable storage-sage
sudo systemctl start storage-sage
sudo systemctl status storage-sage
```

### Docker Compose

```bash
docker compose up -d
docker compose logs -f
```

## Verification

```bash
# Check metrics
curl http://localhost:9090/metrics

# Check API health
curl -k https://localhost:8443/health

# View logs
sudo journalctl -u storage-sage -f
```

## Troubleshooting

### Permission Errors

```bash
sudo chown -R storagesage:storagesage /var/lib/storage-sage
```

### Port Conflicts

```bash
sudo lsof -i :9090
sudo lsof -i :8443
```

### Docker Issues

```bash
docker compose logs storage-sage-backend
docker compose restart
```

## Uninstallation

### Binary

```bash
sudo systemctl stop storage-sage
sudo systemctl disable storage-sage
sudo rm /usr/local/bin/storage-sage*
sudo rm -rf /etc/storage-sage
```

### Docker

```bash
docker compose down -v
docker rmi ghcr.io/ChrisB0-2/storage-sage:latest
```

## Getting Help

- GitHub Issues: https://github.com/ChrisB0-2/storage-sage/issues
- Documentation: https://github.com/ChrisB0-2/storage-sage/wiki
