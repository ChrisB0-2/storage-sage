# StorageSage Unified Startup Guide

Complete guide for starting the entire StorageSage system with **one command**.

---

## Quick Start

```bash
# Build and start everything
./scripts/start-all.sh
```

That's it! The entire system will:
- ✅ Build daemon, backend, and frontend
- ✅ Start all services
- ✅ Verify health endpoints
- ✅ Show access URLs and PIDs

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Prerequisites](#prerequisites)
3. [Directory Structure](#directory-structure)
4. [Build System](#build-system)
5. [Startup Scripts](#startup-scripts)
6. [Systemd Deployment](#systemd-deployment)
7. [Verification](#verification)
8. [Troubleshooting](#troubleshooting)

---

## System Overview

StorageSage consists of **three integrated components**:

| Component | Description | Port | Binary |
|-----------|-------------|------|--------|
| **Daemon** | Cleanup worker with scheduler | 9090 (metrics) | `build/storage-sage` |
| **Backend** | Go REST API server | 8443 (HTTPS) | `build/storage-sage-web` |
| **Frontend** | React UI (CoreUI) | 8443 (via backend) | `web/frontend/dist/` |

### Architecture

```
┌──────────────────────────────────────┐
│  Browser → https://localhost:8443    │
└────────────────┬─────────────────────┘
                 │
         ┌───────▼────────┐
         │  Backend API   │ (Go + React static files)
         │  :8443 HTTPS   │
         └───────┬────────┘
                 │
         ┌───────▼────────┐
         │  Daemon        │ (Cleanup engine)
         │  :9090 metrics │
         └────────────────┘
```

---

## Prerequisites

### Required

- **Go 1.21+** — Daemon and backend
- **Node.js 18+ / npm** — Frontend build
- **OpenSSL** — TLS certificate generation

### Optional

- **curl** — Health check verification
- **lsof** — Port availability checks
- **systemd** — Production deployment

### Verify

```bash
go version       # Go 1.21+
npm --version    # 9.0+
openssl version  # Any recent version
```

---

## Directory Structure

After running the unified build, your directory will look like:

```
storage-sage/
├── build/                      # Compiled binaries
│   ├── storage-sage            # Daemon binary
│   └── storage-sage-web        # Backend binary
│
├── web/
│   ├── frontend/
│   │   ├── dist/               # Frontend production build
│   │   │   ├── index.html
│   │   │   └── assets/
│   │   ├── src/                # React source
│   │   └── package.json
│   │
│   ├── backend/
│   │   └── server.go           # Backend serves frontend/dist
│   │
│   ├── certs/
│   │   ├── server.crt          # TLS certificate (auto-generated)
│   │   └── server.key          # TLS key
│   │
│   └── config/
│       └── config.yaml         # Daemon configuration
│
├── logs/                       # Runtime logs (created on start)
│   ├── daemon.log
│   └── backend.log
│
├── .pids/                      # PID files (created on start)
│   ├── daemon.pid
│   └── backend.pid
│
└── scripts/
    ├── build-all.sh            # ⭐ Unified build
    ├── start-all.sh            # ⭐ Unified startup
    ├── stop-all.sh             # ⭐ Stop all services
    ├── restart-all.sh          # ⭐ Restart all services
    └── install-systemd.sh      # Systemd installation
```

---

## Build System

### **scripts/build-all.sh**

Builds all three components in one command.

```bash
./scripts/build-all.sh
```

**What it does:**
1. Builds Go daemon → `build/storage-sage`
2. Builds Go backend → `build/storage-sage-web`
3. Runs `npm install` (if needed)
4. Builds React frontend → `web/frontend/dist/`
5. Verifies all artifacts exist

**Output:**
```
========================================
  StorageSage Unified Build
========================================

[INFO] Building Go daemon (storage-sage)...
[OK] Daemon built: build/storage-sage

[INFO] Building Go backend (storage-sage-web)...
[OK] Backend built: build/storage-sage-web

[INFO] Building frontend (React app)...
[OK] Frontend built: web/frontend/dist/

[OK] All components built successfully!
```

---

## Startup Scripts

### **scripts/start-all.sh** ⭐

The **main entry point**. Starts everything with one command.

```bash
./scripts/start-all.sh
```

**Features:**
- ✅ Auto-builds if binaries missing
- ✅ Validates environment (Go, npm, ports)
- ✅ Generates TLS certs if missing
- ✅ Starts daemon in background
- ✅ Starts backend in background
- ✅ Runs health checks (daemon metrics + backend API)
- ✅ Shows summary with URLs, PIDs, and next steps

**Options:**

```bash
# Start without rebuilding
./scripts/start-all.sh --no-build

# Run in foreground for debugging
./scripts/start-all.sh --foreground

# Skip health checks
./scripts/start-all.sh --skip-health-check
```

**Environment Variables:**

```bash
# Customize ports
export BACKEND_PORT=8443
export DAEMON_METRICS_PORT=9090

# Set JWT secret (production)
export JWT_SECRET="your-secure-random-secret"

# Override daemon config
export DAEMON_CONFIG="/path/to/config.yaml"

# Start
./scripts/start-all.sh
```

**Output:**

```
========================================
  StorageSage Unified Startup
========================================

[INFO] Validating environment...
[OK] Go: go version go1.21.5 linux/amd64
[OK] npm: 10.2.3
[OK] Environment validated

[INFO] Build artifacts up to date (use --no-build to skip check)

[INFO] Setting up directories...
[OK] Directories created

[INFO] Starting StorageSage daemon...
[OK] Daemon started (PID: 12345)

[INFO] Starting StorageSage backend...
[OK] Backend started (PID: 12346)

[INFO] Running health checks...
[OK] ✓ Daemon metrics: http://localhost:9090/metrics
[OK] ✓ Backend API: https://localhost:8443/api/v1/health

[OK] StorageSage started successfully!
========================================

  Services Running:
    ✓ Storage-Sage Daemon
    ✓ Storage-Sage Backend API
    ✓ Storage-Sage Frontend UI

  Access Points:
    Frontend/UI:  https://localhost:8443
    Backend API:  https://localhost:8443/api/v1
    Daemon Metrics: http://localhost:9090/metrics

  Process IDs:
    Daemon:  12345
    Backend: 12346

  Logs:
    Daemon:  logs/daemon.log
    Backend: logs/backend.log

========================================

Useful commands:
  View daemon logs:  tail -f logs/daemon.log
  View backend logs: tail -f logs/backend.log
  Check status:      ps aux | grep storage-sage
  Stop all:          ./scripts/stop-all.sh
  Restart all:       ./scripts/restart-all.sh
```

---

### **scripts/stop-all.sh**

Gracefully stops all running services.

```bash
./scripts/stop-all.sh
```

**Options:**

```bash
# Force kill (SIGKILL)
./scripts/stop-all.sh --force
```

**What it does:**
1. Stops backend (graceful shutdown)
2. Stops daemon (graceful shutdown)
3. Removes PID files
4. Verifies processes stopped
5. Cleans up orphaned processes

---

### **scripts/restart-all.sh**

Restarts all services (stop + start).

```bash
./scripts/restart-all.sh
```

**Options:**

```bash
# Restart without rebuilding
./scripts/restart-all.sh --no-build

# Force kill on stop, then restart
./scripts/restart-all.sh --force
```

---

## Systemd Deployment

For production environments, use systemd services.

### Install

```bash
# Build first
./scripts/build-all.sh

# Install systemd services (requires root)
sudo ./scripts/install-systemd.sh
```

**What it does:**
1. Creates `storage-sage` system user
2. Copies binaries to `/opt/storage-sage/`
3. Copies config to `/etc/storage-sage/`
4. Generates JWT secret in `/etc/storage-sage/jwt-secret`
5. Installs service files:
   - `/etc/systemd/system/storage-sage-daemon.service`
   - `/etc/systemd/system/storage-sage-backend.service`
6. Reloads systemd

### Enable and Start

```bash
# Enable services (start on boot)
sudo systemctl enable storage-sage-daemon
sudo systemctl enable storage-sage-backend

# Start services
sudo systemctl start storage-sage-daemon
sudo systemctl start storage-sage-backend

# Check status
sudo systemctl status storage-sage-daemon
sudo systemctl status storage-sage-backend
```

### Manage Services

```bash
# Stop
sudo systemctl stop storage-sage-backend storage-sage-daemon

# Restart
sudo systemctl restart storage-sage-backend storage-sage-daemon

# View logs
sudo journalctl -u storage-sage-daemon -f
sudo journalctl -u storage-sage-backend -f
```

---

## Verification

### 1. Check Processes

```bash
ps aux | grep storage-sage
```

Expected output:
```
user  12345  ... build/storage-sage --config web/config/config.yaml
user  12346  ... build/storage-sage-web
```

### 2. Check Daemon Metrics

```bash
curl http://localhost:9090/metrics
```

Expected: Prometheus metrics output.

### 3. Check Backend API

```bash
curl -k https://localhost:8443/api/v1/health
```

Expected:
```json
{"status":"ok"}
```

### 4. Check Frontend UI

Open browser: **https://localhost:8443**

(Accept self-signed certificate warning for dev)

### 5. Check Logs

```bash
# Daemon logs
tail -f logs/daemon.log

# Backend logs
tail -f logs/backend.log
```

---

## Troubleshooting

### Port Already in Use

**Error:**
```
[ERROR] Port 8443 already in use
```

**Fix:**
```bash
# Find process using port
lsof -i :8443

# Kill process or change port
export BACKEND_PORT=8444
./scripts/start-all.sh
```

---

### Build Artifacts Missing

**Error:**
```
[ERROR] Build artifacts missing. Run ./scripts/build-all.sh first
```

**Fix:**
```bash
./scripts/build-all.sh
./scripts/start-all.sh --no-build
```

---

### Frontend Build Fails

**Error:**
```
[ERROR] Frontend build failed
```

**Fix:**
```bash
cd web/frontend
rm -rf node_modules package-lock.json
npm install
npm run build
cd ../..
./scripts/start-all.sh --no-build
```

---

### Health Checks Fail

**Error:**
```
[WARN] ✗ Daemon metrics not responding
```

**Diagnosis:**
```bash
# Check if process is running
ps aux | grep storage-sage

# Check logs for errors
tail -20 logs/daemon.log
tail -20 logs/backend.log

# Test manually
curl -v http://localhost:9090/metrics
curl -kv https://localhost:8443/api/v1/health
```

**Common causes:**
- Config file missing or invalid
- Database initialization failure
- TLS certificate issues (backend)
- Port conflicts

---

### Daemon Fails to Start

**Check config:**
```bash
cat web/config/config.yaml
```

**Verify paths exist:**
```bash
# Daemon creates these on first run
ls -la /var/log/storage-sage
ls -la /var/lib/storage-sage
```

**Check permissions:**
```bash
# Ensure writable by current user
chmod 755 /var/log/storage-sage /var/lib/storage-sage
```

**Run in foreground for debugging:**
```bash
./build/storage-sage --config web/config/config.yaml
```

---

### Backend Fails to Start

**Check TLS certificates:**
```bash
ls -la web/certs/
```

If missing:
```bash
mkdir -p web/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout web/certs/server.key \
  -out web/certs/server.crt \
  -subj "/CN=localhost"
chmod 600 web/certs/server.key
```

**Check frontend build:**
```bash
ls -la web/frontend/dist/index.html
```

If missing:
```bash
cd web/frontend
npm run build
```

**Run in foreground for debugging:**
```bash
cd web
JWT_SECRET="test" ../build/storage-sage-web
```

---

## Advanced Usage

### Custom Configuration

```bash
# Use custom daemon config
export DAEMON_CONFIG="/path/to/custom-config.yaml"
./scripts/start-all.sh
```

### Production Checklist

- [ ] Build release binaries: `go build -ldflags="-s -w"`
- [ ] Set secure JWT secret: `export JWT_SECRET=$(openssl rand -base64 32)`
- [ ] Use valid TLS certificates (not self-signed)
- [ ] Configure firewall rules (allow 8443 only)
- [ ] Set up log rotation
- [ ] Use systemd services for auto-restart
- [ ] Monitor metrics with Prometheus

---

## Summary

| Command | Description |
|---------|-------------|
| `./scripts/build-all.sh` | Build daemon + backend + frontend |
| `./scripts/start-all.sh` | ⭐ **Start entire system** |
| `./scripts/stop-all.sh` | Stop all services |
| `./scripts/restart-all.sh` | Restart all services |
| `sudo ./scripts/install-systemd.sh` | Install systemd services |

**One-liner to start everything:**

```bash
./scripts/start-all.sh
```

**Access the UI:**

```
https://localhost:8443
```

---

**ACE has delivered a fully integrated, single-command StorageSage system. 🚀**
