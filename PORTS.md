# Storage-Sage Port Configuration Reference

## Port Assignments

### Port 8443 - Web Backend API Server (HTTPS)
- **Service**: storage-sage-web (Go backend)
- **Location**: `/home/user/projects/storage-sage/web/backend/server.go` (line 21)
- **Protocol**: HTTPS (TLS 1.3)
- **Purpose**: Serves the React frontend and REST API
- **Endpoints**:
  - `/api/v1/auth/login` - Authentication
  - `/api/v1/health` - Health check
  - `/api/v1/metrics/current` - Metrics (fetches from Prometheus)
  - `/api/v1/config` - Configuration management
  - `/api/v1/cleanup/trigger` - Manual cleanup trigger
  - `/` - Frontend static files

### Port 9090 - Storage-Sage Daemon Metrics Endpoint (HTTP)
- **Service**: storage-sage daemon
- **Location**: Configured in `/etc/storage-sage/config.yaml` or `test-config.yaml`
- **Protocol**: HTTP (Prometheus metrics format)
- **Purpose**: Exposes Prometheus-compatible metrics from the daemon
- **Endpoint**: `/metrics` - Returns Prometheus text format metrics
- **Accessed by**: 
  - Prometheus scrapes from here (when daemon is running)
  - **Note**: Currently daemon is not running; backend fetches from Prometheus instead

### Port 9091 - Prometheus Server (HTTP)
- **Service**: Prometheus monitoring system
- **Location**: Systemd service `/etc/systemd/system/prometheus.service`
- **Protocol**: HTTP
- **Purpose**: Prometheus web UI and API
- **Accessed by**: 
  - Backend API (`routes.go` line 147) fetches metrics from here
  - Grafana queries Prometheus API from here
- **Note**: Backend currently fetches from Prometheus (9091) instead of daemon (9090) because daemon is not running

### Port 3000 - Grafana (HTTP)
- **Service**: Grafana dashboard
- **Protocol**: HTTP
- **Purpose**: Visualization and dashboards for Prometheus data

## Data Flow

```
Browser → Port 8443 (Backend API) → Port 9091 (Prometheus Metrics)
                ↓
         Port 9091 (Prometheus) ← Port 9090 (Daemon Metrics) [when daemon is running]
                ↓
         Port 3000 (Grafana) ← Port 9091 (Prometheus)
```

## Current Configuration Files

### Backend API (`routes.go`)
- **File**: `/home/user/projects/storage-sage/web/backend/api/routes.go`
- **Line**: 147
- **Fetches from**: `http://localhost:9091/metrics` (Prometheus)
- **Serves on**: `https://localhost:8443`
- **Note**: Currently fetches from Prometheus (9091) because daemon (9090) is not running

### Frontend (`Dashboard.tsx`)
- **File**: `/home/user/projects/storage-sage/web/frontend/src/pages/Dashboard.tsx`
- **Line**: 41
- **Calls**: `https://localhost:8443/api/v1/metrics/current`
- **Expects**: Prometheus text format with metric names like:
  - `storagesage_files_deleted_total`
  - `storagesage_bytes_freed_total`
  - `storagesage_errors_total`
  - `storagesage_cleanup_duration_seconds_count`
  - `storagesage_cleanup_duration_seconds_sum`

### Config (`test-config.yaml`)
- **File**: `/home/user/projects/storage-sage/test-config.yaml`
- **Line**: 7
- **Daemon metrics port**: `9090`

### Server Configuration (`server.go`)
- **File**: `/home/user/projects/storage-sage/web/backend/server.go`
- **Line**: 21
- **Backend server port**: `8443` (HTTPS)

## Troubleshooting

### Check if services are running on their ports:

```bash
# Check backend (8443)
sudo lsof -i :8443

# Check daemon metrics (9090)
sudo lsof -i :9090
curl http://localhost:9090/metrics

# Check Prometheus (9091)
sudo lsof -i :9091
curl http://localhost:9091/metrics

# Check Grafana (3000)
sudo lsof -i :3000
curl http://localhost:3000
```

### Verify metrics endpoint:

```bash
# Test daemon metrics directly
curl http://localhost:9090/metrics

# Test through backend API (requires auth token)
curl -k https://localhost:8443/api/v1/metrics/current \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Port Conflicts

If you encounter port conflicts:

1. **Port 8443**: Change `ServerAddr` in `server.go` line 21
2. **Port 9090**: Change `prometheus.port` in config YAML files
3. **Port 9091**: Modify Prometheus systemd service file
4. **Port 3000**: Modify Grafana configuration

## Summary Table

| Port | Service | Protocol | Purpose | Config Location |
|------|---------|----------|---------|----------------|
| 8443 | storage-sage-web | HTTPS | Web UI & API | `server.go:21` |
| 9090 | storage-sage daemon | HTTP | Metrics endpoint | `config.yaml` |
| 9091 | Prometheus | HTTP | Monitoring server | systemd service |
| 3000 | Grafana | HTTP | Dashboards | Grafana config |

