# StorageSage Security Documentation

This document outlines security best practices, implemented security measures, and deployment guidelines for StorageSage.

## Table of Contents

1. [Security Features](#security-features)
2. [Deployment Security](#deployment-security)
3. [Authentication & Authorization](#authentication--authorization)
4. [Network Security](#network-security)
5. [System Hardening](#system-hardening)
6. [Security Checklist](#security-checklist)

## Security Features

### 1. JWT Authentication with RBAC

StorageSage uses JSON Web Tokens (JWT) for authentication with Role-Based Access Control (RBAC).

**Implementation:**
- JWT tokens with configurable expiration (default: 24h)
- Role-based access control (admin, operator, viewer)
- Secure token validation on all protected endpoints

**Best Practices:**
- Store JWT secrets in Docker secrets (not environment variables)
- Generate strong JWT secrets: `openssl rand -base64 32 > secrets/jwt_secret.txt`
- Never commit secrets to version control
- Rotate JWT secrets periodically
- Use short token expiration times for high-security environments

### 2. Rate Limiting

All API endpoints are protected by rate limiting to prevent abuse and DoS attacks.

**Implementation:**
- Global rate limit: 100 requests/second with burst of 200
- Login endpoint: 5 requests/second with burst of 10 (stricter)
- Per-IP address tracking
- Automatic cleanup of old rate limiters

**Configuration:**
Located in `web/backend/server.go`:
```go
// Adjust these values based on your requirements
router.Use(middleware.RateLimitMiddleware(rate.Limit(100), 200))
loginRouter.Use(middleware.RateLimitMiddleware(rate.Limit(5), 10))
```

### 3. Request Body Size Limits

Request bodies are limited to 1MB to prevent memory exhaustion attacks.

**Implementation:**
- Applied globally to all POST, PUT, PATCH requests
- Uses `http.MaxBytesReader` for efficient memory protection
- Returns HTTP 413 (Request Entity Too Large) when exceeded

**Configuration:**
Located in `web/backend/server.go`:
```go
router.Use(middleware.RequestBodySizeLimitMiddleware(1 << 20)) // 1MB
```

### 4. Docker Secrets Management

Sensitive credentials are stored in Docker secrets instead of environment variables.

**Setup:**
```bash
# Generate secure JWT secret
openssl rand -base64 32 > secrets/jwt_secret.txt

# Docker Compose automatically mounts it to /run/secrets/jwt_secret
docker compose up -d
```

**Implementation:**
- JWT secret read from `/run/secrets/jwt_secret`
- Fallback to `JWT_SECRET` env var for backwards compatibility
- Secrets excluded from version control via `.gitignore`

### 5. TLS/HTTPS Configuration

Backend API server uses TLS 1.3 with strong cipher suites.

**Configuration:**
- Minimum TLS version: TLS 1.3
- Cipher suites:
  - `TLS_AES_256_GCM_SHA384`
  - `TLS_AES_128_GCM_SHA256`
  - `TLS_CHACHA20_POLY1305_SHA256`
- Self-signed certificates for development
- Replace with CA-signed certificates for production

**Production Setup:**
```bash
# Use Let's Encrypt or your organization's CA
# Replace files in web/certs/:
#   server.crt (certificate)
#   server.key (private key)
```

## Deployment Security

### Docker Deployment

**Security Features:**
- Non-root execution (UID 1000:1000)
- `no-new-privileges` security option
- Read-only mounts where possible
- SELinux-aware volume mounts (`:z` option)
- Resource limits (memory, CPU)
- Isolated network

**docker-compose.yml Security Options:**
```yaml
storage-sage-backend:
  user: "1000:1000"
  security_opt:
    - no-new-privileges:true
  secrets:
    - jwt_secret
  mem_limit: 512m
```

### SystemD Deployment

**Security Hardening:**

The SystemD service file includes comprehensive security hardening:

```ini
[Service]
User=storage-sage
Group=storage-sage

# Prevent privilege escalation
NoNewPrivileges=true

# Filesystem protection
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/storage-sage /var/lib/storage-sage
ReadOnlyPaths=/etc/storage-sage

# Network restrictions
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

# Kernel hardening
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true

# System call restrictions
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources

# Capabilities (minimal required)
CapabilityBoundingSet=CAP_DAC_OVERRIDE CAP_FOWNER CAP_CHOWN
AmbientCapabilities=CAP_DAC_OVERRIDE CAP_FOWNER

# Resource limits
LimitNOFILE=65536
MemoryMax=512M
TasksMax=100
```

**Setup:**
```bash
# Create system user and directories
sudo ./scripts/setup-systemd-user.sh

# Install and enable service
sudo systemctl enable storage-sage
sudo systemctl start storage-sage
```

## Authentication & Authorization

### User Roles

| Role     | Permissions                                     |
|----------|-------------------------------------------------|
| admin    | Full access: config, metrics, cleanup, logs     |
| operator | Limited: trigger cleanup, view metrics/logs     |
| viewer   | Read-only: view metrics and logs                |

### Default Credentials

**IMPORTANT:** Change default credentials immediately after deployment!

Default admin credentials (defined in backend code):
- Username: `admin`
- Password: `admin123` (CHANGE THIS!)

**Setup:**
1. Log in with default credentials
2. Create new admin user via API or database
3. Delete or disable default admin account
4. Enforce strong password policy

### API Token Management

```bash
# Login to get JWT token
curl -k -X POST https://localhost:8443/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"your-password"}'

# Use token in subsequent requests
curl -k https://localhost:8443/api/v1/metrics/current \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Network Security

### Firewall Configuration

Recommended firewall rules:

```bash
# Allow only necessary ports
# Backend API (HTTPS)
sudo firewall-cmd --permanent --add-port=8443/tcp

# Metrics endpoint (internal only, restrict to monitoring systems)
sudo firewall-cmd --permanent --add-rich-rule='
  rule family="ipv4"
  source address="10.0.0.0/8"
  port port="9090" protocol="tcp" accept'

# Reload firewall
sudo firewall-cmd --reload
```

### SELinux Configuration

StorageSage is SELinux-compatible when run in Docker.

**Volume Mounts:**
```yaml
volumes:
  - /tmp/storage-sage-test-workspace:/test-workspace:z  # :z enables SELinux
  - ./web/config:/etc/storage-sage:rw
```

**Verify SELinux Status:**
```bash
# Check SELinux mode
getenforce  # Should show "Enforcing"

# Check container contexts
docker inspect storage-sage-daemon | grep -i selinux
```

## System Hardening

### File Permissions

```bash
# Configuration files (read-only for service)
chmod 644 /etc/storage-sage/config.yaml
chown storage-sage:storage-sage /etc/storage-sage/config.yaml

# Log directory (write access for service)
chmod 750 /var/log/storage-sage
chown storage-sage:storage-sage /var/log/storage-sage

# Database directory (write access for service)
chmod 750 /var/lib/storage-sage
chown storage-sage:storage-sage /var/lib/storage-sage

# Binary (executable, owned by root)
chmod 755 /usr/local/bin/storage-sage
chown root:root /usr/local/bin/storage-sage
```

### Audit Logging

All deletion operations are logged to multiple destinations:

1. **SQLite Database:** `/var/lib/storage-sage/deletions.db`
   - Permanent record of all deletions
   - Queryable via `storage-sage-query` tool

2. **Loki:** Centralized log aggregation
   - Real-time log streaming
   - Searchable and filterable
   - Integrated with Grafana

3. **Prometheus Metrics:**
   - Counters for files deleted, bytes freed
   - Historical trends
   - Alert-ready

### Monitoring & Alerting

**Key Metrics to Monitor:**
```
# Deletion rate anomalies
rate(storagesage_files_deleted_total[5m]) > threshold

# Error rate
rate(storagesage_errors_total[5m]) > 0

# Memory usage
container_memory_usage_bytes{container="storage-sage-daemon"} > threshold
```

**Grafana Alerts:**
Configure alerts in Grafana for:
- Unusual deletion patterns
- High error rates
- Service downtime
- Disk space issues

## Security Checklist

### Pre-Deployment

- [ ] Generate strong JWT secret: `openssl rand -base64 32 > secrets/jwt_secret.txt`
- [ ] Replace self-signed TLS certificates with CA-signed certificates
- [ ] Change default admin password
- [ ] Review and adjust rate limits based on expected load
- [ ] Configure firewall rules to restrict access
- [ ] Set up SELinux policies if using SystemD deployment
- [ ] Create dedicated `storage-sage` system user

### Post-Deployment

- [ ] Verify non-root execution: `docker exec storage-sage-daemon id`
- [ ] Test JWT authentication with valid and invalid tokens
- [ ] Verify rate limiting works (send rapid requests)
- [ ] Check logs for any security warnings
- [ ] Set up monitoring and alerting
- [ ] Document incident response procedures
- [ ] Schedule regular security audits

### Ongoing Maintenance

- [ ] Rotate JWT secrets every 90 days
- [ ] Review audit logs weekly
- [ ] Update TLS certificates before expiration
- [ ] Monitor for dependency vulnerabilities: `go list -m all | nancy sleuth`
- [ ] Apply security patches promptly
- [ ] Review and update firewall rules
- [ ] Conduct periodic penetration testing

## Reporting Security Issues

If you discover a security vulnerability in StorageSage:

1. **DO NOT** open a public GitHub issue
2. Email security concerns to: [security@your-organization.com]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

We will respond within 48 hours and work with you to address the issue.

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)
- [SystemD Hardening Guide](https://www.freedesktop.org/software/systemd/man/systemd.exec.html)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
