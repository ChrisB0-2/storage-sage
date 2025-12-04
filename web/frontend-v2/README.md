# StorageSage Frontend v2

Modern React admin dashboard for StorageSage built with CoreUI React Admin Template.

## Features

- **Overview Dashboard** - Real-time disk usage metrics and cleanup statistics
- **Cleanup Rules** - Configure global settings and per-path cleanup rules
- **Deletion History** - Paginated view of all deleted files
- **System Health** - Monitor service health and systemd integration

## Quick Start

### Prerequisites

- Node.js >= 16
- npm >= 8
- StorageSage backend running on `http://localhost:9090`

### Installation

```bash
cd web/frontend-v2
npm install
```

### Development

Run the development server with hot reload:

```bash
npm run dev
```

The app will be available at [http://localhost:3000](http://localhost:3000)

### Production Build

Build the production-ready static files:

```bash
npm run build
```

The built files will be in the `build/` directory.

### Preview Production Build

Test the production build locally:

```bash
npm run preview
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

Edit `.env`:

```env
REACT_APP_API_BASE_URL=http://localhost:9090
```

### API Endpoints

The frontend expects these backend endpoints:

- `GET /api/metrics` - System metrics
- `GET /api/config` - Configuration
- `PUT /api/config` - Update configuration
- `GET /api/deletions?limit=100` - Deletion history
- `POST /api/cleanup` - Trigger manual cleanup
- `GET /health` - Health check

## Project Structure

```
web/frontend-v2/
├── src/
│   ├── api/
│   │   └── storageSageClient.js      # API client
│   ├── components/
│   │   ├── AppContent.js              # Main content router
│   │   ├── AppFooter.js               # Footer component
│   │   ├── AppHeader.js               # Header with navigation
│   │   ├── AppSidebar.js              # Sidebar container
│   │   └── AppSidebarNav.js           # Sidebar navigation
│   ├── layout/
│   │   └── DefaultLayout.js           # Main layout wrapper
│   ├── scss/
│   │   ├── style.scss                 # Main styles
│   │   └── _variables.scss            # SCSS variables
│   ├── views/
│   │   └── storagesage/
│   │       ├── Overview.js            # Dashboard page
│   │       ├── CleanupRules.js        # Config editor
│   │       ├── Deletions.js           # Deletion history
│   │       └── SystemHealth.js        # System health
│   ├── _nav.js                        # Navigation config
│   ├── routes.js                      # Route definitions
│   ├── store.js                       # Redux store
│   ├── App.js                         # Root component
│   └── index.js                       # Entry point
├── .env                               # Environment config
├── .env.example                       # Environment template
├── package.json                       # Dependencies
├── vite.config.js                     # Vite config
└── index.html                         # HTML template
```

## Integration with Backend

### Serving Frontend from Backend

Update your Go backend to serve the built frontend:

```go
// Serve static frontend files
fs := http.FileServer(http.Dir("./web/frontend-v2/build"))
http.Handle("/", fs)

// API routes
http.HandleFunc("/api/metrics", metricsHandler)
http.HandleFunc("/api/config", configHandler)
// ... other API routes
```

### CORS Configuration

If running frontend and backend on different ports during development, ensure CORS is enabled:

```go
func enableCORS(w http.ResponseWriter) {
    w.Header().Set("Access-Control-Allow-Origin", "http://localhost:3000")
    w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
}
```

## Development Workflow

1. **Start backend**: Ensure StorageSage backend is running
2. **Start frontend**: `npm run dev`
3. **Make changes**: Edit files in `src/`
4. **Build for production**: `npm run build`
5. **Test production**: `npm run preview`

## Technologies

- **React 18** - UI library
- **React Router v6** - Routing
- **CoreUI 5** - UI component library
- **Axios** - HTTP client
- **Vite** - Build tool
- **Redux** - State management (minimal usage)

## Troubleshooting

### API Connection Issues

Check that:
1. Backend is running on the configured port (default: 9090)
2. `.env` has correct `REACT_APP_API_BASE_URL`
3. CORS is enabled if running on different ports

### Build Errors

Clear cache and reinstall:
```bash
rm -rf node_modules package-lock.json
npm install
```

### Port Already in Use

Change dev server port in `vite.config.js`:
```js
server: {
  port: 3001,  // Change to any available port
}
```

## License

Same as StorageSage main project.
