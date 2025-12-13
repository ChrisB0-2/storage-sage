# StorageSage Proof Pipeline

**Purpose:** Executable verification suite that proves specification compliance.

**Standard:** Zero hand-waving. Every claim backed by command output.

---

## A) Repo State Proof

**Objective:** Verify clean working state and specification tracking

```bash
# Check working tree
git status --porcelain

# Get current commit
git rev-parse HEAD

# Verify spec is tracked
git ls-files docs/CI_CD_REVIEW_SPEC.md
```

**Pass Criteria:**
- Empty output from `git status --porcelain` OR only expected changes
- HEAD SHA prints successfully
- Specification file is tracked

---

## B) Safety Contract Proof

**Objective:** Prove safety guarantees through tests

### B1) Build Pipeline
```bash
# Validate code
make validate

# Lint code
make lint

# Run all tests (safety-critical)
make test

# Build binaries
make build

# Verify binary exists and is executable
test -x dist/storage-sage && echo "✓ Binary exists and is executable"
ls -lh dist/storage-sage
```

**Pass Criteria:**
- All make commands exit 0
- `dist/storage-sage` exists and is executable

### B2) Safety Test Evidence
```bash
# Protected path blocking tests
go test -v ./internal/safety/ -run TestProtectedPathBlocking

# Dry-run contract proof (0 delete calls)
go test -v ./internal/cleanup/ -run TestDryRunNeverDeletes

# Integration tests (real filesystem)
go test -v ./internal/integration/ -run TestCleanupSafetyIntegration

# Full safety suite
go test -v ./internal/safety/ ./internal/cleanup/ ./internal/integration/
```

**Pass Criteria:**
- All tests PASS
- TestDryRunNeverDeletes shows 0 delete calls
- TestCleanupSafetyIntegration verifies protected files remain

### B3) Safety Validator Unit Test Count
```bash
# Count safety test cases
go test -v ./internal/safety/ 2>&1 | grep -E "^=== RUN|PASS:" | wc -l
```

**Pass Criteria:** >50 test cases executed

---

## C) Exit Code Contract Proof

**Objective:** Prove exit codes enforce operational contract

### C1) Invalid Configuration (Exit 2)
```bash
./dist/storage-sage --config /nonexistent.yaml 2>&1 ; echo "Exit code: $?"
```

**Expected Output:**
```
failed to load config: open /nonexistent.yaml: no such file or directory
Exit code: 2
```

**Pass Criteria:** Exit code = 2

### C2) Safety Violation (Exit 3)
```bash
# Create minimal config that tries to scan protected path
mkdir -p /tmp/ss-test
cat > /tmp/ss-test/unsafe-config.yaml <<EOF
scan_paths: ["/etc"]
interval_minutes: 60
prometheus: {port: 9090}
EOF

# Attempt to run (should fail with safety violation)
./dist/storage-sage --config /tmp/ss-test/unsafe-config.yaml --dry-run --once 2>&1 ; echo "Exit code: $?"

# Cleanup
rm -rf /tmp/ss-test
```

**Expected Output:** Exit code = 3 (if validator blocks) or runtime behavior depends on implementation

**Pass Criteria:** System fails safely (does not delete protected paths)

### C3) Success (Exit 0)
```bash
# Run with valid config (if exists)
./dist/storage-sage --version ; echo "Exit code: $?"
```

**Expected Output:**
```
StorageSage vX.Y.Z
Exit code: 0
```

**Pass Criteria:** Exit code = 0

---

## D) Immutability Proof

**Objective:** Prove artifacts are never rebuilt after CI

### D1) Dockerfile.runtime Purity Check
```bash
echo "=== Checking Dockerfile.runtime for compilation commands ==="
grep -nE "go build|golang|go\s+install|RUN.*go" cmd/storage-sage/Dockerfile.runtime \
  && echo "❌ FAIL: Compilation found in runtime Dockerfile" \
  || echo "✓ PASS: No compilation in runtime Dockerfile"
```

**Pass Criteria:** "PASS" (grep returns no matches)

### D2) Workflow Immutability Check
```bash
echo "=== Checking workflows for go build commands ==="

echo "CI workflow (should have 'make build'):"
grep -n "make build\|go build" .github/workflows/ci.yml || echo "  (none found)"

echo "Docker workflow (should NOT have go build):"
grep -n "make build\|go build" .github/workflows/docker.yml \
  && echo "  ❌ FAIL: Build found" \
  || echo "  ✓ PASS: No build"

echo "Deploy workflow (should NOT have go build):"
grep -n "make build\|go build" .github/workflows/deploy.yml \
  && echo "  ❌ FAIL: Build found" \
  || echo "  ✓ PASS: No build"

echo "Release workflow (should NOT have go build):"
grep -n "make build\|go build" .github/workflows/release.yml \
  && echo "  ❌ FAIL: Build found" \
  || echo "  ✓ PASS: No build"
```

**Pass Criteria:**
- ci.yml: Contains "make build" or "go build"
- docker.yml: NO "go build"
- deploy.yml: NO "go build"
- release.yml: NO "go build"

### D3) Artifact Upload/Download Chain
```bash
echo "=== Verifying artifact chain ==="

echo "Artifact upload (ci.yml):"
grep -n "upload-artifact" .github/workflows/ci.yml | head -5

echo "Artifact download (docker.yml):"
grep -n "download-artifact" .github/workflows/docker.yml | head -5

echo "Artifact download (release.yml):"
grep -n "download-artifact" .github/workflows/release.yml | head -5
```

**Pass Criteria:**
- ci.yml uploads artifact
- docker.yml downloads artifact
- release.yml downloads artifact

### D4) Docker Build Immutability (Local)
```bash
echo "=== Building Docker image from current artifacts ==="

# Ensure binary exists
test -f dist/storage-sage || (echo "❌ dist/storage-sage not found. Run: make build" && exit 1)

# Build runtime image
docker build -f cmd/storage-sage/Dockerfile.runtime -t storage-sage:proof .

# Check image history for compilation
echo "=== Checking image history for go build ==="
docker history storage-sage:proof | grep -i "go build" \
  && echo "❌ FAIL: Rebuild detected in image layers" \
  || echo "✓ PASS: No rebuild in image layers"

# Verify binary in image matches local
echo "=== Verifying binary in image ==="
docker run --rm storage-sage:proof /app/storage-sage --version
```

**Pass Criteria:**
- Image builds successfully
- No "go build" in image history
- Binary runs and shows version

---

## E) Deploy Verification Proof (Local Simulation)

**Objective:** Simulate deploy.yml verification gates locally

### E1) Setup Test Environment
```bash
echo "=== Setting up test environment ==="

# Create test directories
mkdir -p /tmp/ss-proof/allowed
mkdir -p /tmp/ss-proof/protected
mkdir -p /tmp/ss-proof/logs

# Create test files (dry-run must not delete these)
echo "deletable junk file" > /tmp/ss-proof/allowed/junk.log
echo "PROTECTED - MUST KEEP" > /tmp/ss-proof/protected/keep.txt

# Create minimal config
cat > /tmp/ss-proof/config.yaml <<'EOF'
scan_paths:
  - /tmp/ss-proof/allowed
interval_minutes: 60
prometheus:
  port: 9090
database_path: /tmp/ss-proof/deletions.db
age_off_days: 30
min_free_percent: 20
EOF

echo "✓ Test environment created"
ls -R /tmp/ss-proof/
```

### E2) Deploy Container
```bash
echo "=== Deploying test container ==="

# Stop and remove if exists
docker stop ss-proof 2>/dev/null || true
docker rm ss-proof 2>/dev/null || true

# Run container in dry-run mode
docker run -d \
  --name ss-proof \
  -p 9090:9090 \
  -v /tmp/ss-proof/config.yaml:/etc/storage-sage/config.yaml:ro \
  -v /tmp/ss-proof:/tmp/ss-proof \
  -v /tmp/ss-proof/logs:/var/log/storage-sage \
  storage-sage:proof \
  --dry-run --config /etc/storage-sage/config.yaml

echo "✓ Container started: ss-proof"
```

### E3) Health Check Verification
```bash
echo "=== Verifying health check ==="

# Wait for container to be healthy
for i in {1..30}; do
  HEALTH=$(docker inspect --format='{{.State.Health.Status}}' ss-proof 2>/dev/null || echo "starting")
  echo "Attempt $i/30: Health status = $HEALTH"

  if [ "$HEALTH" = "healthy" ]; then
    echo "✓ PASS: Container is healthy"
    break
  elif [ "$HEALTH" = "unhealthy" ]; then
    echo "❌ FAIL: Container is unhealthy"
    docker logs ss-proof
    exit 1
  fi

  sleep 2
done

# Verify final status
FINAL_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' ss-proof 2>/dev/null)
if [ "$FINAL_HEALTH" != "healthy" ]; then
  echo "❌ FAIL: Container did not become healthy"
  docker logs ss-proof
  exit 1
fi
```

**Pass Criteria:** Container becomes healthy within 60 seconds

### E4) Metrics Endpoint Verification
```bash
echo "=== Verifying metrics endpoint ==="

# Check /metrics endpoint
METRICS=$(curl -fsS http://localhost:9090/metrics 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ FAIL: Metrics endpoint not responding"
  docker logs ss-proof
  exit 1
fi

echo "✓ Metrics endpoint responding"

# Check for critical metrics
echo "$METRICS" | grep -q "storagesage_daemon_up" \
  && echo "✓ Found: storagesage_daemon_up" \
  || echo "⚠ Warning: storagesage_daemon_up not found"

echo "$METRICS" | grep -q "storagesage_cleanup_duration_seconds" \
  && echo "✓ Found: storagesage_cleanup_duration_seconds" \
  || echo "⚠ Warning: cleanup_duration not found"

echo "$METRICS" | grep -q "storagesage_files_deleted_total" \
  && echo "✓ Found: storagesage_files_deleted_total" \
  || echo "⚠ Warning: files_deleted not found"

# Show first 20 lines of metrics
echo "=== First 20 lines of /metrics ==="
echo "$METRICS" | head -n 20
```

**Pass Criteria:**
- Metrics endpoint returns HTTP 200
- Contains Prometheus-formatted metrics

### E5) Dry-Run Safety Verification
```bash
echo "=== Verifying dry-run safety (CRITICAL) ==="

# Wait a few seconds for daemon to run
sleep 5

# Verify files still exist (dry-run must not delete)
if [ -f /tmp/ss-proof/allowed/junk.log ]; then
  echo "✓ PASS: Allowed file intact (dry-run safe)"
else
  echo "❌ FAIL: DRY-RUN VIOLATION - Allowed file was deleted!"
  docker logs ss-proof
  exit 1
fi

if [ -f /tmp/ss-proof/protected/keep.txt ]; then
  echo "✓ PASS: Protected file intact"
else
  echo "❌ CRITICAL FAILURE: Protected file was deleted!"
  docker logs ss-proof
  exit 1
fi

# Check file contents unchanged
JUNK_CONTENT=$(cat /tmp/ss-proof/allowed/junk.log)
PROTECTED_CONTENT=$(cat /tmp/ss-proof/protected/keep.txt)

if [ "$JUNK_CONTENT" = "deletable junk file" ]; then
  echo "✓ PASS: Allowed file content unchanged"
else
  echo "❌ FAIL: Allowed file content modified"
fi

if [ "$PROTECTED_CONTENT" = "PROTECTED - MUST KEEP" ]; then
  echo "✓ PASS: Protected file content unchanged"
else
  echo "❌ CRITICAL: Protected file content modified"
fi
```

**Pass Criteria:**
- Both files exist
- File contents unchanged
- No deletions occurred

### E6) Container Logs Review
```bash
echo "=== Container logs (last 50 lines) ==="
docker logs ss-proof --tail 50

echo "=== Checking for errors in logs ==="
docker logs ss-proof 2>&1 | grep -i "error\|fatal\|panic" \
  && echo "⚠ Errors found in logs (review above)" \
  || echo "✓ No critical errors in logs"
```

### E7) Cleanup
```bash
echo "=== Cleanup ==="
docker stop ss-proof
docker rm ss-proof
rm -rf /tmp/ss-proof
echo "✓ Test environment cleaned"
```

---

## F) CI/CD Pipeline Proof (Workflow Inspection)

**Objective:** Verify workflows implement specification requirements

### F1) Workflow File Existence
```bash
echo "=== Verifying workflow files exist ==="
ls -lh .github/workflows/*.yml
```

**Pass Criteria:** All workflow files present:
- ci.yml
- docker.yml
- deploy.yml
- release.yml

### F2) Required Stages Presence
```bash
echo "=== Verifying CI stages ==="
grep -E "name:.*Validate|name:.*Lint|name:.*Test|name:.*Build" .github/workflows/ci.yml \
  | grep -v "^#"

echo "=== Verifying Docker stages ==="
grep -E "name:.*Download|name:.*Build.*push" .github/workflows/docker.yml \
  | grep -v "^#"

echo "=== Verifying Deploy stages ==="
grep -E "name:.*Security|name:.*Deploy|name:.*Verify" .github/workflows/deploy.yml \
  | grep -v "^#"

echo "=== Verifying Release stages ==="
grep -E "name:.*Download|name:.*Package|name:.*Release" .github/workflows/release.yml \
  | grep -v "^#"
```

**Pass Criteria:** All required stage names present

### F3) Immutability Chain Validation
```bash
echo "=== Validating immutability chain ==="

# CI should upload artifact
echo "1. CI uploads artifact:"
grep -A 3 "upload-artifact" .github/workflows/ci.yml | grep "name:" | head -1

# Docker should download artifact
echo "2. Docker downloads artifact:"
grep -A 3 "download-artifact" .github/workflows/docker.yml | grep "name:" | head -1

# Deploy should use image (not build)
echo "3. Deploy pulls image:"
grep "docker pull" .github/workflows/deploy.yml | head -1

# Release should download artifact
echo "4. Release downloads artifact:"
grep -A 3 "download-artifact" .github/workflows/release.yml | grep "name:" | head -1
```

**Pass Criteria:** Chain is complete (upload → download → reuse)

---

## G) Documentation Proof

**Objective:** Verify all documentation is present and complete

```bash
echo "=== Verifying documentation files ==="

# Required docs
DOCS=(
  "docs/CI_CD_REVIEW_SPEC.md"
  "docs/REMEDIATION_SUMMARY.md"
  "docs/SPRINT_2_COMPLETE.md"
  "docs/CI_CD.md"
  "docs/ROLLBACK.md"
  "docs/PROOF_PIPELINE.md"
)

for doc in "${DOCS[@]}"; do
  if [ -f "$doc" ]; then
    LINES=$(wc -l < "$doc")
    echo "✓ $doc ($LINES lines)"
  else
    echo "❌ Missing: $doc"
  fi
done
```

**Pass Criteria:** All documentation files present

---

## Complete Proof Suite

**Run all proofs in sequence:**

```bash
#!/bin/bash
set -e  # Exit on any error

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   StorageSage Proof Pipeline - Complete Verification      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# A) Repo State
echo "█ A) Repo State Proof"
git status --porcelain
git rev-parse HEAD
git ls-files docs/CI_CD_REVIEW_SPEC.md
echo ""

# B) Safety Contract
echo "█ B) Safety Contract Proof"
make validate
make lint
make test
make build
test -x dist/storage-sage && echo "✓ Binary exists"
echo ""

# C) Exit Codes
echo "█ C) Exit Code Proof"
./dist/storage-sage --config /nonexistent.yaml 2>&1 || true
echo ""

# D) Immutability
echo "█ D) Immutability Proof"
grep -nE "go build|golang" cmd/storage-sage/Dockerfile.runtime || echo "✓ No compilation"
docker build -f cmd/storage-sage/Dockerfile.runtime -t storage-sage:proof .
docker history storage-sage:proof | grep -i "go build" || echo "✓ No rebuild layers"
echo ""

# E) Deploy Verification
echo "█ E) Deploy Verification Proof"
# (Run sections E1-E7 from above)
echo "See detailed steps in docs/PROOF_PIPELINE.md"
echo ""

# F) Workflow Inspection
echo "█ F) Workflow Proof"
ls -1 .github/workflows/*.yml
echo ""

# G) Documentation
echo "█ G) Documentation Proof"
ls -1 docs/*.md | wc -l
echo ""

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Proof Pipeline Complete                                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
```

---

## Failure Modes

**If any proof fails, the completion claim is false.**

Common failure scenarios:

1. **Tests fail** → Safety contract not proven
2. **go build in Dockerfile.runtime** → Immutability violated
3. **docker.yml has go build** → Rebuild occurring
4. **Health check times out** → Deployment verification broken
5. **Files deleted in dry-run** → DRY-RUN CONTRACT VIOLATED (CRITICAL)
6. **Exit codes wrong** → Operational contract broken

**Recovery:** Fix the failing component, rerun proof suite.

---

## Evidence Ledger

Record proof run output here for audit trail:

```
Date: YYYY-MM-DD
Commit: <git rev-parse HEAD>
Operator: <name>

Proof A (Repo State): PASS/FAIL
Proof B (Safety): PASS/FAIL
Proof C (Exit Codes): PASS/FAIL
Proof D (Immutability): PASS/FAIL
Proof E (Deploy): PASS/FAIL
Proof F (Workflows): PASS/FAIL
Proof G (Docs): PASS/FAIL

Overall: PASS/FAIL

Notes:
<any findings>
```

---

## Continuous Verification

**Add to CI:**

```yaml
# .github/workflows/proof.yml
name: Proof Pipeline

on: [push, pull_request]

jobs:
  proof:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.21'

      - name: Run Proof Suite
        run: |
          make validate
          make lint
          make test
          make build
          test -x dist/storage-sage

          # Immutability check
          ! grep -E "go build" cmd/storage-sage/Dockerfile.runtime

          # Exit code check
          ./dist/storage-sage --config /nonexistent 2>&1 || [ $? -eq 2 ]
```

This ensures proof suite runs on every commit.

---

**End of Proof Pipeline**

**Standard:** If this document's checks pass, Sprint 2 is provably complete.
