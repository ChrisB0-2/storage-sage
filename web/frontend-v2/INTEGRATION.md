# Backend Integration Guide

This document explains how to integrate the StorageSage frontend with the Go backend.

## Option 1: Serve Frontend from Go Backend (Recommended)

### Step 1: Build the Frontend

```bash
cd web/frontend-v2
npm run build
```

This creates production files in `web/frontend-v2/build/`

### Step 2: Update Go Backend to Serve Static Files

Add this to your main Go server file (e.g., `cmd/storagesage/main.go`):

```go
package main

import (
    "embed"
    "io/fs"
    "log"
    "net/http"
)

//go:embed web/frontend-v2/build/*
var frontendFS embed.FS

func main() {
    // API routes
    http.HandleFunc("/api/metrics", handleMetrics)
    http.HandleFunc("/api/config", handleConfig)
    http.HandleFunc("/api/deletions", handleDeletions)
    http.HandleFunc("/api/cleanup", handleCleanup)
    http.HandleFunc("/health", handleHealth)
    http.HandleFunc("/metrics", handlePrometheusMetrics)

    // Serve frontend static files
    frontendStaticFS, err := fs.Sub(frontendFS, "web/frontend-v2/build")
    if err != nil {
        log.Fatal(err)
    }

    fileServer := http.FileServer(http.FS(frontendStaticFS))
    http.Handle("/", fileServer)

    log.Println("Server starting on :9090")
    log.Fatal(http.ListenAndServe(":9090", nil))
}
```

### Step 3: Handle SPA Routing

For React Router to work, serve `index.html` for all non-API routes:

```go
func spaHandler(fsys fs.FS) http.HandlerFunc {
    fileServer := http.FileServer(http.FS(fsys))

    return func(w http.ResponseWriter, r *http.Request) {
        // API routes - don't handle here
        if strings.HasPrefix(r.URL.Path, "/api/") ||
           strings.HasPrefix(r.URL.Path, "/health") ||
           strings.HasPrefix(r.URL.Path, "/metrics") {
            http.NotFound(w, r)
            return
        }

        // Try to serve the file
        path := r.URL.Path
        f, err := fsys.Open(strings.TrimPrefix(path, "/"))
        if err != nil {
            // File doesn't exist, serve index.html for SPA routing
            r.URL.Path = "/"
        }
        if f != nil {
            f.Close()
        }

        fileServer.ServeHTTP(w, r)
    }
}

// Use it:
http.HandleFunc("/", spaHandler(frontendStaticFS))
```

## Option 2: Run Separately During Development

### Frontend (Port 3000)

```bash
cd web/frontend-v2
npm run dev
```

### Backend (Port 9090)

```bash
cd cmd/storagesage
go run main.go
```

### Enable CORS in Backend

Add CORS middleware:

```go
func enableCORS(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "http://localhost:3000")
        w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

        if r.Method == "OPTIONS" {
            w.WriteHeader(http.StatusOK)
            return
        }

        next(w, r)
    }
}

// Wrap API handlers
http.HandleFunc("/api/metrics", enableCORS(handleMetrics))
http.HandleFunc("/api/config", enableCORS(handleConfig))
// ... etc
```

## Required API Endpoints

The frontend expects these endpoints:

### GET /api/metrics

Returns system metrics in JSON:

```json
{
  "disk": {
    "total": 1000000000000,
    "used": 750000000000,
    "free": 250000000000
  },
  "cleanup": {
    "total_deletions": 1234,
    "space_freed": 50000000000,
    "last_run": "2025-11-24T10:30:00Z",
    "next_run": "2025-11-25T02:00:00Z",
    "enabled": true,
    "total_runs": 42
  },
  "thresholds": {
    "warning_percent": 75,
    "critical_percent": 90
  }
}
```

### GET /api/config

Returns configuration:

```json
{
  "global": {
    "max_age_days": 30,
    "min_size_mb": 100,
    "warning_threshold": 75,
    "critical_threshold": 90,
    "schedule": "0 2 * * *"
  },
  "per_path_rules": [
    {
      "path": "/var/log",
      "max_age_days": 7,
      "min_size_mb": 10,
      "pattern": "*.log"
    }
  ]
}
```

### PUT /api/config

Accepts same JSON structure as GET, updates config:

```go
func handleConfig(w http.ResponseWriter, r *http.Request) {
    if r.Method == "GET" {
        // Return current config
        json.NewEncoder(w).Encode(currentConfig)
    } else if r.Method == "PUT" {
        // Update config
        var newConfig Config
        if err := json.NewDecoder(r.Body).Decode(&newConfig); err != nil {
            http.Error(w, err.Error(), http.StatusBadRequest)
            return
        }
        // Save and apply new config
        currentConfig = newConfig
        json.NewEncoder(w).Encode(currentConfig)
    }
}
```

### GET /api/deletions?limit=100

Returns deletion history:

```json
[
  {
    "path": "/var/log/old.log",
    "size": 104857600,
    "deleted_at": "2025-11-24T12:00:00Z",
    "reason": "age",
    "age_days": 45
  }
]
```

### POST /api/cleanup

Triggers manual cleanup:

```json
{
  "status": "success",
  "files_deleted": 10,
  "space_freed": 524288000,
  "duration_seconds": 2.5
}
```

### GET /health

Health check endpoint:

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime_seconds": 3600,
  "started_at": "2025-11-24T10:00:00Z"
}
```

## Build for Production

### 1. Build Frontend

```bash
cd web/frontend-v2
npm run build
```

### 2. Build Go Binary with Embedded Frontend

```bash
cd cmd/storagesage
go build -o storagesage
```

The `//go:embed` directive embeds the built frontend into the binary.

### 3. Deploy

Copy the single binary to your server:

```bash
scp storagesage user@server:/usr/local/bin/
```

### 4. Run as Systemd Service

Create `/etc/systemd/system/storagesage.service`:

```ini
[Unit]
Description=StorageSage Disk Management Service
After=network.target

[Service]
Type=simple
User=storagesage
ExecStart=/usr/local/bin/storagesage
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable storagesage
sudo systemctl start storagesage
```

## Environment Variables

The frontend uses:

- `REACT_APP_API_BASE_URL` - API base URL (default: `http://localhost:9090`)

For production, you don't need to change this if serving from the same origin.

## Troubleshooting

### Frontend can't connect to backend

1. Check backend is running: `curl http://localhost:9090/health`
2. Check CORS headers if running separately
3. Verify `.env` has correct API URL

### 404 on page refresh

Ensure SPA handler redirects all non-API routes to `index.html`

### Build size too large

The build includes code splitting. If needed, optimize:

```js
// vite.config.js
build: {
  rollupOptions: {
    output: {
      manualChunks: {
        'vendor': ['react', 'react-dom'],
      },
    },
  },
}
```

## Next Steps

1. Implement all required API endpoints in Go
2. Test locally with `npm run dev`
3. Build production bundle with `npm run build`
4. Integrate with Go backend using embed
5. Deploy as systemd service
