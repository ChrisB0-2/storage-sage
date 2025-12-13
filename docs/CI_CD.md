# StorageSage CI/CD Pipeline Documentation

## Overview

StorageSage implements a **professional-grade CI/CD pipeline** that enforces the safety contract and ensures immutable artifact delivery.

## Core Principles

1. **Build Once, Deploy Everywhere** - Artifacts are built once in CI and reused in all downstream stages
2. **Tested Artifact == Deployed Artifact** - No rebuilds after testing
3. **Safety by Gate** - Each stage proves a contract before proceeding
4. **Fail Closed** - Any failure blocks deployment

---

## Pipeline Architecture

```
┌─────────────┐
│   Push to   │
│    main     │
└──────┬──────┘
       │
       v
┌─────────────────────────────────────────┐
│         CI Workflow (ci.yml)            │
│  ┌─────────┐  ┌──────┐  ┌──────┐      │
│  │Validate │→ │ Lint │→ │ Test │→     │
│  └─────────┘  └──────┘  └──────┘  │   │
│                                    v   │
│                              ┌─────────┐│
│                              │  Build  ││
│                              └────┬────┘│
│                                   │     │
│                                   v     │
│                         Upload Artifact │
│                         binaries-{SHA}  │
└─────────────────────────┬───────────────┘
                          │
                          v
        ┌─────────────────────────────────┐
        │   Docker Workflow (docker.yml)  │
        │  ┌────────────────────────┐     │
        │  │ Download Artifact      │     │
        │  │ (no rebuild)           │     │
        │  └───────┬────────────────┘     │
        │          v                      │
        │  ┌────────────────────────┐     │
        │  │ Build Runtime Image    │     │
        │  │ (Dockerfile.runtime)   │     │
        │  └───────┬────────────────┘     │
        │          v                      │
        │  Push: ghcr.io/.../sha-{SHA}   │
        └──────────┬─────────────────────┘
                   │
                   v
        ┌─────────────────────────────────┐
        │  Deploy Workflow (deploy.yml)   │
        │  ┌────────────────────────┐     │
        │  │ Security Scan (Trivy)  │     │
        │  └───────┬────────────────┘     │
        │          v                      │
        │  ┌────────────────────────┐     │
        │  │ Deploy Test            │     │
        │  │ (docker run)           │     │
        │  └───────┬────────────────┘     │
        │          v                      │
        │  ┌────────────────────────┐     │
        │  │ Verify                 │     │
        │  │ - /metrics             │     │
        │  │ - Health check         │     │
        │  │ - Dry-run safety       │     │
        │  └────────────────────────┘     │
        └─────────────────────────────────┘
                   │
                   v
              Production
              Deployment
```

---

## Workflows

### 1. CI Workflow (`.github/workflows/ci.yml`)

**Trigger:** Push to `main`, `develop`, or pull requests

**Purpose:** Build and test code, produce immutable artifact

**Stages:**

1. **Validate** (`make validate`)
   - Runs `go fmt` and `go vet`
   - Fast fail on formatting/syntax issues

2. **Lint** (`make lint`)
   - Runs `golangci-lint`
   - Enforces code quality standards

3. **Test** (`make test`)
   - Runs all unit tests, integration tests
   - Executes on matrix: [ubuntu, macos] × [go 1.21, 1.22]
   - Generates coverage report
   - **Proves safety contract:**
     - Protected paths blocked
     - Symlink escapes detected
     - Dry-run = 0 deletions
     - Traversal blocked

4. **Build** (`make build`)
   - Builds binaries: `dist/storage-sage`, `dist/storage-sage-query`
   - Uploads artifact: `binaries-{SHA}`
   - **THIS IS THE SINGLE SOURCE ARTIFACT**

5. **Docker** (parallel)
   - Downloads `binaries-{SHA}`
   - Builds test image using `Dockerfile.runtime`
   - **NO compilation in Docker build**

**Artifacts Produced:**
- `binaries-{SHA}` - Tested binaries (30-day retention)
- `binaries` - Latest binaries (7-day retention)

**Exit Criteria:**
- All tests pass (100% safety tests must pass)
- Binaries build successfully
- Coverage uploaded to Codecov

---

### 2. Docker Workflow (`.github/workflows/docker.yml`)

**Trigger:** After CI workflow completes (workflow_run)

**Purpose:** Package tested artifact into Docker image

**Immutability Guarantee:** Downloads `binaries-{SHA}` from CI, **never rebuilds**

**Process:**

1. Download artifact `binaries-{SHA}` from CI workflow
2. Verify binaries exist
3. Build Docker image using `Dockerfile.runtime`:
   - Base: `alpine:latest`
   - COPY pre-built `dist/storage-sage` into image
   - NO `go build` command in Dockerfile
4. Push image with tags:
   - `sha-{SHA}` (immutable, permanent)
   - `main` (rolling, latest main)

**Image Tags:**
- `ghcr.io/{repo}:sha-{SHA}` - Immutable, tied to specific commit
- `ghcr.io/{repo}:main` - Rolling tag for latest main

**Exit Criteria:**
- Artifact successfully downloaded
- Image built without errors
- Image pushed to registry

---

### 3. Deploy & Verify Workflow (`.github/workflows/deploy.yml`)

**Trigger:** After Docker workflow completes

**Purpose:** Security scan + deploy to test + verify deployment

**Stages:**

#### 3a. Security Scan

Uses Trivy to scan Docker image for vulnerabilities

```yaml
- Scans: ghcr.io/{repo}:sha-{SHA}
- Reports: SARIF to GitHub Security tab
- Fails on: CRITICAL vulnerabilities
```

**Exit Criteria:**
- No CRITICAL vulnerabilities
- Scan results uploaded to Security tab

#### 3b. Deploy Test

Deploys container locally to verify deployment process

```bash
docker run -d \
  --name storage-sage-test \
  -p 9090:9090 \
  -v /tmp/test-config:/etc/storage-sage:ro \
  ghcr.io/{repo}:sha-{SHA} \
  --config /etc/storage-sage/config.yaml --dry-run
```

Creates test filesystem structure:
- `/tmp/storage-sage-test/allowed/` - Files that can be deleted
- `/tmp/storage-sage-test/protected/` - Files that must never be touched

**Exit Criteria:**
- Container starts successfully
- Health check passes (within 60 seconds)
- No startup errors in logs

#### 3c. Verify

Proves deployment contract through automated tests

**Verification Tests:**

1. **Metrics Endpoint** (`/metrics`)
   ```bash
   curl http://localhost:9090/metrics | grep "storagesage_daemon_up"
   ```
   - Verifies Prometheus metrics are exposed
   - Checks for critical metrics presence

2. **Dry-Run Safety**
   ```bash
   # Verify files still exist (dry-run should not delete)
   test -f /tmp/storage-sage-test/allowed/junk.log
   test -f /tmp/storage-sage-test/protected/keep.txt
   ```
   - Proves dry-run contract: no deletions occurred
   - Verifies protected files untouched

3. **Database Initialization**
   ```bash
   test -f /var/lib/storage-sage/deletions.db
   ```
   - Verifies database created successfully

**Exit Criteria:**
- All verification tests pass
- No files deleted during dry-run
- Protected files remain intact

---

### 4. Release Workflow (`.github/workflows/release.yml`)

**Trigger:** Push to tag `v*` (e.g., `v1.0.0`)

**Purpose:** Create GitHub Release with tested artifacts

**Immutability Guarantee:** Downloads `binaries-{SHA}`, **does not rebuild**

**Process:**

1. Download `binaries-{SHA}` from CI workflow
2. Package binaries:
   ```bash
   tar -czf storage-sage-linux-amd64.tar.gz storage-sage
   sha256sum *.tar.gz > checksums.txt
   ```
3. Generate release notes (includes safety guarantees)
4. Create GitHub Release with:
   - Binary packages (`.tar.gz`)
   - Checksums (`checksums.txt`)
   - Release notes
5. Build and push Docker image with version tags:
   - `ghcr.io/{repo}:{version}` (e.g., `v1.0.0`)
   - `ghcr.io/{repo}:latest`

**Exit Criteria:**
- Release created successfully
- All artifacts attached
- Docker image tagged with version

---

## Immutability Contract

**The Specification Requires:**
> "Build once. Store artifact or image (tagged by commit SHA). Deploy must reuse that artifact. Rebuild during deploy = BLOCKER."

**Our Implementation:**

### Artifact Flow

```
CI (ci.yml)
  └─> go build → dist/storage-sage
      └─> Upload artifact: binaries-{SHA}
          │
          ├─> Docker (docker.yml)
          │   └─> Download binaries-{SHA}
          │       └─> COPY dist/storage-sage → Image
          │           └─> NO go build in Dockerfile
          │
          ├─> Deploy (deploy.yml)
          │   └─> Pull ghcr.io/.../sha-{SHA}
          │       └─> Run container
          │           └─> Verify
          │
          └─> Release (release.yml)
              └─> Download binaries-{SHA}
                  └─> Package → .tar.gz
                      └─> Attach to GitHub Release
```

**Proof Points:**

1. ✅ **Single Build**: Only `ci.yml` contains `go build`
2. ✅ **Artifact Reuse**: Docker/Deploy/Release download `binaries-{SHA}`
3. ✅ **No Rebuilds**: `Dockerfile.runtime` uses `COPY`, not `go build`
4. ✅ **SHA Tagging**: Images tagged with commit SHA (immutable)
5. ✅ **Tested == Deployed**: Same binary tested in CI is deployed

---

## Exit Codes

StorageSage uses standardized exit codes for operational monitoring:

| Exit Code | Meaning | CI Behavior |
|-----------|---------|-------------|
| 0 | Success | Continue |
| 2 | Invalid configuration | Fail fast |
| 3 | Safety violation | **CRITICAL - Rollback** |
| 4 | Runtime error | Retry or alert |

CI/CD uses these codes to make deployment decisions:
- Exit 3 (safety violation) → Immediate rollback
- Exit 2 (invalid config) → Block deployment, fix config
- Exit 4 (runtime error) → Alert operators

---

## Safety Gates

Each stage proves a safety guarantee:

### CI Stage Safety Proofs

**Unit Tests (`internal/safety/validator_test.go`):**
- ✅ Protected paths blocked: 22 test cases
- ✅ Traversal blocked: 7 test cases
- ✅ Symlink escapes detected: 4 test cases
- ✅ Allowed roots enforced: 7 test cases

**Dry-Run Tests (`internal/cleanup/dryrun_test.go`):**
- ✅ Proves dry-run = 0 filesystem syscalls (FakeDeleter)
- ✅ Proves real mode calls deleter correctly

**Integration Tests (`internal/integration/cleanup_safety_integration_test.go`):**
- ✅ Real filesystem verification
- ✅ Symlink escape blocking
- ✅ Protected path enforcement

### Deploy Stage Safety Proofs

**Dry-Run Verification:**
```bash
# Before: files exist
test -f /tmp/storage-sage-test/allowed/junk.log
test -f /tmp/storage-sage-test/protected/keep.txt

# Run: storage-sage --dry-run

# After: files MUST still exist (dry-run = no deletions)
test -f /tmp/storage-sage-test/allowed/junk.log || exit 1
test -f /tmp/storage-sage-test/protected/keep.txt || exit 1
```

If verification fails → deployment blocked

---

## Local Development

### Run CI Locally

```bash
# Validate
make validate

# Lint
make lint

# Test (runs all safety tests)
make test

# Build
make build

# Verify artifact
ls -lh dist/storage-sage
./dist/storage-sage --version
```

### Test Docker Build Locally

```bash
# Build using CI process
make build

# Build Docker image using runtime Dockerfile
docker build -f cmd/storage-sage/Dockerfile.runtime -t storage-sage:local .

# Run locally
docker run --rm storage-sage:local --version
```

### Test Deploy Process Locally

```bash
# Create test config
mkdir -p /tmp/test-config
cat > /tmp/test-config/config.yaml <<EOF
scan_paths: ["/tmp/allowed"]
interval_minutes: 60
prometheus:
  port: 9090
EOF

# Run container
docker run -d \
  --name test \
  -p 9090:9090 \
  -v /tmp/test-config:/etc/storage-sage:ro \
  storage-sage:local \
  --dry-run --config /etc/storage-sage/config.yaml

# Verify
curl http://localhost:9090/metrics

# Cleanup
docker stop test && docker rm test
```

---

## Troubleshooting

### CI Failures

**Test Failures:**
```bash
# Run specific test locally
go test -v ./internal/safety/ -run TestProtectedPathBlocking

# Check test coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

**Build Failures:**
```bash
# Check Go version
go version  # Should be 1.21+

# Clean build
rm -rf dist/
make build
```

### Docker Build Failures

**Artifact Not Found:**
```
ERROR: dist/storage-sage not found
```

**Solution:** Ensure `make build` completed successfully before Docker build

**Permission Denied:**
```
ERROR: Cannot copy dist/storage-sage: permission denied
```

**Solution:** Check file permissions:
```bash
chmod +x dist/storage-sage dist/storage-sage-query
```

### Deploy Failures

**Health Check Timeout:**
```
Container never became healthy
```

**Solution:** Check logs:
```bash
docker logs storage-sage-test
```

Common causes:
- Invalid configuration
- Missing volumes
- Port conflicts

---

## Metrics & Monitoring

### CI Metrics

- **Build Duration**: Track via GitHub Actions timing
- **Test Pass Rate**: Must be 100% for safety tests
- **Artifact Size**: Monitor `dist/storage-sage` size

### Deployment Metrics

Exposed at `/metrics`:

```
# Daemon health
storagesage_daemon_up

# Cleanup metrics
storagesage_cleanup_duration_seconds
storagesage_files_deleted_total
storagesage_bytes_freed_total

# Safety metrics
storagesage_daemon_errors_total
storagesage_daemon_free_space_percent
```

---

## Compliance

This CI/CD pipeline satisfies all requirements from `docs/CI_CD_REVIEW_SPEC.md`:

✅ **Section F: CI/CD Pipeline Requirements**
- validate, test, build, package, security, deploy_test, verify stages
- Immutability: build once, deploy that artifact
- Deploy only from main or tags
- No rebuilds during deploy

✅ **Section G: Deployment Verification**
- `/metrics` endpoint verified
- Health check automated
- Dry-run verification post-deploy
- Protected paths verified untouched

✅ **Section H: Rollback**
- Previous images retained (SHA-tagged)
- Rollback documented in `docs/ROLLBACK.md`
- `make rollback VERSION=x.y.z` command available

---

## References

- **CI/CD Specification:** `docs/CI_CD_REVIEW_SPEC.md`
- **Remediation Summary:** `docs/REMEDIATION_SUMMARY.md`
- **Rollback Procedures:** `docs/ROLLBACK.md`
- **Safety Documentation:** `internal/safety/validator.go`
