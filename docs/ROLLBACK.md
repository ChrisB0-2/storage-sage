# StorageSage Rollback Procedures

## Overview

This document provides the operational contract for rolling back StorageSage deployments in case of failures.

## Quick Rollback Command

```bash
# Rollback to previous version
make rollback VERSION=<previous-tag-or-sha>
```

## Docker Rollback (Production)

### 1. Identify Previous Version

```bash
# List recent images
docker images ghcr.io/yourusername/storage-sage

# Example output:
# ghcr.io/yourusername/storage-sage   v1.0.1    abc123   2 days ago   50MB
# ghcr.io/yourusername/storage-sage   v1.0.0    def456   1 week ago   48MB
```

### 2. Rollback Using Docker Compose

```bash
# Stop current version
docker compose down

# Edit docker-compose.yml to use previous image tag
# Change: image: ghcr.io/yourusername/storage-sage:v1.0.1
# To:     image: ghcr.io/yourusername/storage-sage:v1.0.0

# Start previous version
docker compose up -d

# Verify rollback
docker compose ps
docker compose logs -f storage-sage-daemon
```

### 3. Quick Rollback with Tag Override

```bash
# Export previous version tag
export STORAGE_SAGE_VERSION=v1.0.0

# Restart with override
docker compose down
docker compose up -d

# Verify
curl -s http://localhost:9090/metrics | grep version
```

## Binary Rollback (Daemon Only)

### 1. Download Previous Binary

```bash
# Download from GitHub releases
wget https://github.com/yourusername/storage-sage/releases/download/v1.0.0/storage-sage-linux-amd64

# Or use previously saved artifact
cp /var/backups/storage-sage/storage-sage-v1.0.0 /usr/local/bin/storage-sage

# Verify binary
/usr/local/bin/storage-sage --version
```

### 2. Restart Service

```bash
# Systemd
sudo systemctl restart storage-sage
sudo systemctl status storage-sage

# Verify
curl -s http://localhost:9090/metrics
```

## Verification After Rollback

```bash
# 1. Check service health
curl -s http://localhost:9090/metrics | grep up

# 2. Check version
/usr/local/bin/storage-sage --version

# 3. Run dry-run to verify safety
/usr/local/bin/storage-sage --dry-run --once --config /etc/storage-sage/config.yaml

# 4. Check logs for errors
tail -f /var/log/storage-sage/daemon.log
```

## Database Rollback (If Schema Changed)

If the new version introduced database schema changes:

```bash
# 1. Stop daemon
sudo systemctl stop storage-sage

# 2. Restore database backup
cp /var/backups/storage-sage/deletions.db.backup /var/lib/storage-sage/deletions.db

# 3. Start previous version
sudo systemctl start storage-sage
```

## Preventive Measures

### Automatic Backups Before Deploy

```bash
# Add to deployment script
#!/bin/bash
set -e

# Backup current binary
cp /usr/local/bin/storage-sage /var/backups/storage-sage/storage-sage-$(date +%Y%m%d-%H%M%S)

# Backup database
cp /var/lib/storage-sage/deletions.db /var/backups/storage-sage/deletions.db.$(date +%Y%m%d-%H%M%S)

# Deploy new version
# ... deployment steps ...
```

### Retention Policy

```bash
# Keep last 5 versions
cd /var/backups/storage-sage
ls -t storage-sage-* | tail -n +6 | xargs rm -f
ls -t deletions.db.* | tail -n +6 | xargs rm -f
```

## Makefile Rollback Command

Add to Makefile:

```makefile
rollback: ## Rollback to previous version
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: VERSION not specified. Usage: make rollback VERSION=v1.0.0"; \
		exit 1; \
	fi
	@echo "Rolling back to version $(VERSION)..."
	docker compose down
	docker pull ghcr.io/$(GITHUB_REPOSITORY):$(VERSION)
	docker tag ghcr.io/$(GITHUB_REPOSITORY):$(VERSION) storage-sage:latest
	docker compose up -d
	@echo "✓ Rollback complete. Verify with: make health-check"
```

## Emergency Rollback (Critical Failures)

If the daemon is causing system issues:

```bash
# 1. IMMEDIATE STOP
sudo systemctl stop storage-sage
docker compose down

# 2. Disable auto-restart
sudo systemctl disable storage-sage

# 3. Investigate logs
journalctl -u storage-sage -n 100

# 4. Rollback when ready
# ... follow standard rollback procedure ...

# 5. Re-enable after verification
sudo systemctl enable storage-sage
sudo systemctl start storage-sage
```

## CI/CD Automated Rollback

GitHub Actions rollback workflow (`.github/workflows/rollback.yml`):

```yaml
name: Rollback

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to rollback to (e.g., v1.0.0)'
        required: true
        type: string

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
      - name: Validate version
        run: |
          echo "Rolling back to version: ${{ github.event.inputs.version }}"

      - name: Deploy previous version
        run: |
          # Pull previous image
          docker pull ghcr.io/${{ github.repository }}:${{ github.event.inputs.version }}

          # Update deployment (example - adapt to your deployment method)
          # kubectl set image deployment/storage-sage storage-sage=ghcr.io/${{ github.repository }}:${{ github.event.inputs.version }}
```

## Exit Codes for Rollback Decision

StorageSage uses specific exit codes to help determine if rollback is needed:

| Exit Code | Meaning | Rollback? |
|-----------|---------|-----------|
| 0 | Success | No |
| 2 | Invalid config | No (fix config) |
| 3 | Safety violation | **YES** (critical) |
| 4 | Runtime error | Maybe (investigate) |

**Automatic rollback trigger**: Exit code 3 (safety violation) should trigger immediate rollback.

## Contact / Escalation

For rollback assistance:
1. Check logs: `/var/log/storage-sage/`
2. Check metrics: `http://localhost:9090/metrics`
3. Review recent changes: `git log --oneline -10`
4. File incident report with logs attached

## Testing Rollback Procedure

Regularly test rollback in staging:

```bash
# Monthly rollback drill
1. Deploy latest version
2. Verify functionality
3. Execute rollback to N-1 version
4. Verify functionality
5. Document any issues
```
