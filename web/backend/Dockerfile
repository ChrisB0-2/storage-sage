# ============================================
# STAGE 1: Build Frontend
# ============================================
FROM node:20-alpine AS frontend-builder

WORKDIR /build/frontend

# Copy frontend package files
COPY web/frontend/package.json web/frontend/package-lock.json* ./

# Install dependencies (use npm ci if package-lock exists, otherwise npm install)
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# Copy frontend source
COPY web/frontend/ ./

# Build frontend (Vite outputs to dist/)
RUN npm run build

# Verify build output
RUN ls -la dist/ && test -f dist/index.html || (echo "ERROR: Frontend build failed - dist/index.html not found" && exit 1)

# ============================================
# STAGE 2: Build Go Backend
# ============================================
FROM golang:1.24-alpine AS backend-builder

WORKDIR /build

# Install build dependencies (including sqlite for CGO)
RUN apk add --no-cache git ca-certificates tzdata wget gcc musl-dev sqlite-dev

# Copy go mod files first for better caching
COPY go.mod go.sum ./
COPY web/backend/go.mod web/backend/go.sum ./web/backend/

# Download dependencies
RUN go mod download
WORKDIR /build/web/backend
RUN go mod download
WORKDIR /build

# Copy entire project (needed for internal packages)
COPY . .

# Fix: Update backend dependencies to include transitive deps from parent module
WORKDIR /build/web/backend
RUN go mod tidy

# Build web server binary with CGO enabled for sqlite support
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /build/storage-sage-web \
    .
WORKDIR /build

# ============================================
# STAGE 3: Production Image (NON-ROOT)
# ============================================
FROM alpine:3.19

# Install runtime dependencies including sqlite
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    wget \
    sqlite \
    sqlite-libs

# Create non-root user and group
RUN addgroup -g 1000 -S storagesage && \
    adduser -u 1000 -S storagesage -G storagesage

# Create necessary directories with proper ownership
RUN mkdir -p /app/certs /app/logs /app/frontend/dist && \
    chown -R storagesage:storagesage /app

# Copy binary from backend builder
COPY --from=backend-builder /build/storage-sage-web /app/storage-sage-web
RUN chown storagesage:storagesage /app/storage-sage-web && \
    chmod +x /app/storage-sage-web

# Copy frontend build artifacts from frontend builder
COPY --from=frontend-builder --chown=storagesage:storagesage /build/frontend/dist /app/frontend/dist

# Set working directory
WORKDIR /app

# Switch to non-root user
USER storagesage

# Expose HTTPS port
EXPOSE 8443

# Health check (HTTPS)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-check-certificate -qO- https://localhost:8443/api/v1/health || exit 1

# Run the web server
ENTRYPOINT ["/app/storage-sage-web"]