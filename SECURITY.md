# Security Policy

## Supported Versions

We actively support the following versions of StorageSage with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please follow responsible disclosure practices:

### How to Report

**DO NOT** open a public GitHub issue for security vulnerabilities.

Instead, please report security vulnerabilities by:

1. **Email**: Send details to **security@example.com** (update with actual contact)
2. **Private GitHub Security Advisory**: Use GitHub's private vulnerability reporting feature
   - Go to https://github.com/ChrisB0-2/storage-sage/security/advisories
   - Click "Report a vulnerability"

### What to Include

Please provide the following information:

- **Description**: Clear description of the vulnerability
- **Impact**: Potential security impact and affected components
- **Reproduction Steps**: Detailed steps to reproduce the issue
- **Proof of Concept**: Code, commands, or screenshots demonstrating the vulnerability
- **Environment**: OS, version, configuration details
- **Suggested Fix**: If you have recommendations (optional)

### Response Timeline

- **Initial Response**: Within 48 hours of report
- **Status Update**: Within 7 days with preliminary assessment
- **Fix Timeline**: Critical issues within 30 days, others within 90 days
- **Public Disclosure**: After patch release, coordinated with reporter

### Security Update Process

1. Vulnerability is verified and assessed
2. Fix is developed and tested
3. Security advisory is prepared
4. Patch is released with security notes
5. Public disclosure after users have time to update

## Security Best Practices

### Deployment Security

#### 1. Authentication & Authorization

- **Never use default credentials**
- Generate strong JWT secrets:
  ```bash
  openssl rand -base64 32 > secrets/jwt_secret.txt
  ```
- Use Docker secrets for sensitive data (preferred over environment variables)
- Implement API rate limiting (configured in .env)
- Regularly rotate JWT secrets and tokens

#### 2. TLS/SSL Configuration

- **Never use self-signed certificates in production**
- Obtain certificates from trusted CA (Let's Encrypt, etc.)
- Configure strong TLS settings:
  - TLS 1.2 minimum (TLS 1.3 preferred)
  - Strong cipher suites only
  - Disable weak protocols (SSL, TLS 1.0, TLS 1.1)
- Set proper file permissions on private keys:
  ```bash
  chmod 600 /path/to/server.key
  chown root:root /path/to/server.key
  ```

#### 3. File System Permissions

- Run daemon with dedicated non-root user:
  ```bash
  sudo useradd -r -s /bin/false storagesage
  ```
- Set restrictive permissions on sensitive directories:
  ```bash
  sudo chown -R storagesage:storagesage /var/lib/storage-sage
  sudo chmod 700 /var/lib/storage-sage
  sudo chmod 600 /var/lib/storage-sage/deletions.db
  ```
- Use read-only mounts where possible (NFS mounts)

#### 4. Network Security

- Use firewall rules to restrict access:
  ```bash
  # Allow only from specific IPs
  sudo ufw allow from 192.168.1.0/24 to any port 8443
  sudo ufw allow from 192.168.1.0/24 to any port 9090
  ```
- Consider using reverse proxy (nginx, Traefik) for additional security
- Enable HTTPS only (disable HTTP)
- Use network policies in Kubernetes environments

#### 5. Container Security

- Use official images from GitHub Container Registry
- Verify image signatures and checksums
- Run containers with non-root user
- Limit container capabilities:
  ```yaml
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  cap_add:
    - CHOWN
    - DAC_OVERRIDE  # Only if needed for file operations
  ```
- Use read-only root filesystem where possible
- Regularly update base images

#### 6. Database Security

- Encrypt database at rest (use LUKS or similar)
- Restrict database file permissions (600)
- Regularly backup database with encryption
- Sanitize deletion history logs (may contain sensitive paths)

#### 7. Secrets Management

**Preferred Order** (most secure to least):
1. **Docker Secrets** (for Docker Swarm)
2. **Kubernetes Secrets** (for K8s)
3. **HashiCorp Vault** (enterprise)
4. **File-based secrets** with strict permissions
5. **Environment variables** (least secure)

Never:
- Commit secrets to version control
- Log secrets in application logs
- Store secrets in container images
- Share secrets over insecure channels

#### 8. Logging & Monitoring

- Enable audit logging for all deletions
- Monitor for suspicious activity:
  - Unusual deletion patterns
  - Failed authentication attempts
  - Privilege escalation attempts
- Send logs to centralized logging (Loki, ELK)
- Set up alerts for security events
- Regularly review logs

#### 9. Input Validation

- All configuration files are validated against schema
- File paths are sanitized to prevent path traversal
- API inputs are validated and sanitized
- Rate limiting prevents abuse

#### 10. Updates & Patching

- Subscribe to security advisories
- Regularly update StorageSage to latest version
- Keep base OS and dependencies updated
- Test updates in staging before production

### Configuration Security

#### Minimal Privilege Configuration

```yaml
# Example secure configuration
rules:
  - name: "logs-cleanup"
    paths:
      - "/var/log/app"  # Specific paths only
    conditions:
      age_days: 30
      min_size_bytes: 0
    actions:
      delete: true
    safety:
      dry_run: false
      require_confirmation: true
      preserve_count: 5  # Keep at least 5 newest files
```

#### Dangerous Configurations to Avoid

```yaml
# ❌ DANGEROUS - Never do this
rules:
  - paths:
      - "/"  # Never monitor root
      - "/home"  # Too broad
      - "/etc"  # System files
    conditions:
      age_days: 1  # Too aggressive
```

### Docker Compose Security

```yaml
services:
  storage-sage-backend:
    # Use specific version tags
    image: ghcr.io/ChrisB0-2/storage-sage:v1.0.0
    
    # Run as non-root
    user: "1000:1000"
    
    # Read-only root filesystem
    read_only: true
    
    # Drop all capabilities
    cap_drop:
      - ALL
    
    # Prevent privilege escalation
    security_opt:
      - no-new-privileges:true
    
    # Use secrets instead of env vars
    secrets:
      - jwt_secret
    
    # Resource limits
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M

secrets:
  jwt_secret:
    file: ./secrets/jwt_secret.txt
```

## Known Security Considerations

### File Deletion Operations

- **Irreversible**: Deleted files cannot be recovered
- **Race Conditions**: Files can be deleted while being accessed
- **Permission Requirements**: Daemon needs write access to target directories
- **Audit Trail**: All deletions are logged to database

### Web API Exposure

- Default port 8443 exposes HTTPS API
- Requires JWT authentication
- Rate limited by default
- Should be behind firewall or reverse proxy

### Metrics Endpoint

- Port 9090 exposes Prometheus metrics
- No authentication by default (Prometheus standard)
- May leak information about filesystem structure
- Should be restricted to monitoring network

## Security Checklist

Before deploying to production:

- [ ] Generate strong JWT secret (32+ bytes)
- [ ] Replace self-signed certificates with CA-signed
- [ ] Configure firewall rules
- [ ] Run daemon as non-root user
- [ ] Set strict file permissions (700/600)
- [ ] Enable audit logging
- [ ] Configure rate limiting
- [ ] Set up monitoring and alerts
- [ ] Use read-only mounts where possible
- [ ] Test backup and restore procedures
- [ ] Document disaster recovery plan
- [ ] Review and test cleanup rules (dry-run first)
- [ ] Subscribe to security advisories

## Compliance

### Data Protection

- **GDPR**: Audit logs may contain personal information (file paths)
- **Data Retention**: Configure retention policies for audit logs
- **Right to Erasure**: Implement procedures to purge audit logs
- **Access Controls**: Restrict access to audit database

### Industry Standards

- Follow OWASP Top 10 guidelines
- Implement defense in depth
- Principle of least privilege
- Regular security audits

## Security Contacts

- **Security Issues**: security@example.com (update with actual contact)
- **General Support**: https://github.com/ChrisB0-2/storage-sage/issues
- **Security Advisories**: https://github.com/ChrisB0-2/storage-sage/security/advisories

## Acknowledgments

We appreciate responsible disclosure and will acknowledge security researchers who report vulnerabilities (with permission).

---

**Last Updated**: 2024-12-04
**Version**: 1.0.0
