# Changelog

All notable changes to StorageSage will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Enhanced policy engine with complex rule combinations
- S3-compatible object storage support
- Real-time filesystem event monitoring (inotify/fsnotify)
- Email notification integration
- Slack/Discord webhook notifications
- Multi-tenant support
- Advanced reporting and analytics
- Machine learning-based cleanup predictions

## [1.0.0] - 2024-12-04

### Added
- Initial public release
- Core daemon for automated filesystem cleanup
- Age-based and size-based cleanup rules
- SQLite database for deletion audit trail
- Prometheus metrics endpoint for monitoring
- RESTful API backend with JWT authentication
- React-based web frontend with real-time dashboard
- Query tool for deletion history (`storage-sage-query`)
- Docker and Docker Compose support
- Systemd service integration
- TLS/HTTPS support with certificate generation
- Comprehensive configuration via YAML
- Dry-run mode for safe testing
- Grafana dashboard template
- Multi-architecture support (AMD64, ARM64)
- Cross-platform support (Linux, macOS)
- Package distribution (deb, rpm, apk)
- GoReleaser configuration for automated releases

### Security
- JWT-based API authentication
- TLS encryption for web traffic
- API rate limiting
- Docker secrets support
- Audit logging for all deletions
- Non-root container execution
- File permission validation

### Documentation
- Installation guide (INSTALL.md)
- Security policy (SECURITY.md)
- Code of conduct (CODE_OF_CONDUCT.md)
- Comprehensive README
- API documentation
- Configuration examples

---

## Release Notes Format

### Types of Changes
- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Removed features
- **Fixed** - Bug fixes
- **Security** - Security fixes and improvements

## Upgrade Guide

### From Pre-1.0 to 1.0.0

This is the initial stable release. If you were using development versions:

1. **Backup your database**:
   ```bash
   cp /var/lib/storage-sage/deletions.db /var/lib/storage-sage/deletions.db.backup
   ```

2. **Update configuration format**: The YAML configuration format is now stable. Review `test-config.yaml` for the canonical format.

3. **Update environment variables**: See `.env.example` for new required variables.

4. **Regenerate TLS certificates** (if using self-signed):
   ```bash
   make setup
   ```

5. **Restart services**:
   ```bash
   # Systemd
   sudo systemctl restart storage-sage
   
   # Docker
   docker compose down
   docker compose up -d
   ```

## Version History

- **1.0.0** (2024-12-04) - Initial stable release

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Reporting bugs
- Suggesting enhancements
- Submitting pull requests
- Development workflow

## Links

- **Repository**: https://github.com/ChrisB0-2/storage-sage
- **Issues**: https://github.com/ChrisB0-2/storage-sage/issues
- **Releases**: https://github.com/ChrisB0-2/storage-sage/releases
- **Docker Images**: https://github.com/ChrisB0-2/storage-sage/pkgs/container/storage-sage

---

[Unreleased]: https://github.com/ChrisB0-2/storage-sage/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ChrisB0-2/storage-sage/releases/tag/v1.0.0
