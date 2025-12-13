# StorageSage CI/CD Professionalization Review Spec

## Purpose

This document defines the **non-negotiable engineering requirements** for making StorageSage a **professional, production-grade CI/CD system**.

StorageSage is **destructive-capable infrastructure software**.  
CI/CD exists here to **prevent irreversible failure**, not just to “run tests.”

Claude Code is asked to:
- Review the repository against this spec
- Identify gaps
- Propose concrete code or pipeline changes
- Flag any violation as **BLOCKER**

---

## Core Principles (Must Hold)

1. **Safety by Contract**
   - Unsafe deletions must be *impossible by construction*, not merely unlikely.

2. **Single Source of Truth for Safety**
   - All delete decisions must route through one audited code path.

3. **Dry-Run Is Non-Destructive**
   - Dry-run must *never* delete under any circumstance.

4. **Immutable Delivery**
   - CI builds once.
   - CD deploys that *exact artifact*.
   - Rebuilds during deploy are forbidden.

---

## A) Mandatory Safety Guardrails (Code)

### Centralized Path Validation API (Required)

StorageSage **must** expose a single safety module responsible for all delete authorization.

Required functions (names flexible, behavior not):

- NormalizePath(path) → absolute, cleaned path
- IsProtectedPath(path) → blocks system-critical paths
- IsWithinAllowedRoots(path, allowedRoots)
- DetectTraversal(path) → blocks `..`
- DetectSymlinkEscape(path, root)
- ValidateDeleteTarget(path, allowedRoots) → returns typed error

### Protected Paths (Minimum)

Deletion must be refused for:
- `/`
- `/etc`
- `/bin`
- `/usr`
- `/lib*`
- `/boot`
- Any configurable protected list

### Hard Contract

A delete operation **must not execute** unless:
- Path is inside allowed roots
- Path is not protected
- Path does not escape via symlink
- Path does not traverse via `..`

Any violation = **safety error**

---

## B) Dry-Run Contract (Code + Tests)

### Requirements

- Dry-run mode must never invoke real delete syscalls
- Delete operations must be routed through an interface:
  - Allows fake/mock deleter in tests
- CI tests must assert:
  - Zero delete calls during dry-run
  - Logs/metrics indicate “would delete”

### Violations

- Any code path where dry-run could delete = **BLOCKER**

---

## C) Exit Codes (Operational Contract)

StorageSage must use consistent exit codes:

| Code | Meaning |
|----|----|
| 0 | Success |
| 2 | Invalid configuration |
| 3 | Safety violation |
| 4 | Runtime error |

CI and operators rely on these.

---

## D) Testing Requirements (CI Gates)

### Unit Tests (Table-Driven)

Must exist for:
- Protected path blocking
- Allowed root enforcement
- Path normalization
- Traversal detection (`..`)
- Symlink escape detection

### Integration Test (Filesystem)

CI must:
1. Create a temporary filesystem:
   - allowed/ (junk files)
   - protected/ (must never be touched)
   - symlink escaping allowed root
2. Run StorageSage:
   - Dry-run → assert no deletion
   - Execute → assert only allowed deletes
3. Verify real disk state

If integration test missing → **BLOCKER**

---

## E) Build Standardization

Project must expose deterministic commands:

- `make validate`
- `make test`
- `make build` → outputs `dist/storage-sage`
- `make lint`

CI **must not** call ad-hoc commands.

---

## F) CI/CD Pipeline Requirements (GitLab)

### Required Stages (Exact Order)

1. validate
2. test
3. build
4. package
5. security
6. deploy_test
7. verify
8. release (tags only)

### Rules

- Validate/test/build on every MR + main
- Deploy only from main or tags
- Release only on `vX.Y.Z` tags

### Immutability Rule

- Build once
- Store artifact or image (tagged by commit SHA)
- Deploy must reuse that artifact
- Rebuild during deploy = **BLOCKER**

---

## G) Deployment Verification (CD Is Real)

After deployment, CI must verify:

- `/healthz` returns OK
- Metrics endpoint reachable
- Dry-run cleanup against test tree succeeds safely
- No protected paths touched

---

## H) Rollback (Minimum Viable)

At minimum:
- Previous artifact/image retained
- One documented rollback command exists

---

## Reviewer Instructions (Claude Code)

Claude Code should:

1. Audit code for **safety enforcement**
2. Verify tests *prove* safety, not assume it
3. Check CI pipeline enforces immutability
4. Flag any missing requirement as **BLOCKER**
5. Propose concrete fixes (code, tests, YAML)

Do **not** accept:
- “This is unlikely”
- “Handled elsewhere”
- “Operationally safe”
- “Best practice”

Only **provable guarantees** are acceptable.

---

## Single Highest Priority Rule

If only one requirement is enforced:

> **StorageSage must never delete protected paths or escape allowed roots — under any condition.**

Any ambiguity here invalidates the system.
