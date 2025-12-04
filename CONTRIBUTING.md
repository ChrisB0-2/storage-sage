# Contributing to StorageSage

Thank you for your interest in contributing to StorageSage! This document provides guidelines and instructions for contributing.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Setup](#development-setup)
4. [Making Changes](#making-changes)
5. [Testing](#testing)
6. [Submitting Changes](#submitting-changes)
7. [Code Style](#code-style)
8. [Commit Messages](#commit-messages)
9. [Review Process](#review-process)

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow. Please be respectful and constructive in all interactions.

### Our Standards

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Accept constructive criticism gracefully
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

### Ways to Contribute

- **Report Bugs**: Submit detailed bug reports
- **Suggest Features**: Propose new features or improvements
- **Write Documentation**: Improve or add documentation
- **Submit Code**: Fix bugs or implement new features
- **Review PRs**: Help review pull requests
- **Answer Questions**: Help others in discussions

### Before You Start

1. Check existing [issues](https://github.com/ChrisB0-2/storage-sage/issues) and [pull requests](https://github.com/ChrisB0-2/storage-sage/pulls)
2. For major changes, open an issue first to discuss the approach
3. Make sure you can commit to completing the work

## Development Setup

### Prerequisites

- Go 1.23 or later
- Git
- Make
- Docker and Docker Compose (optional, for integration testing)
- SQLite development libraries

### Fork and Clone

```bash
# Fork the repository on GitHub, then:
git clone https://github.com/YOUR_USERNAME/storage-sage.git
cd storage-sage

# Add upstream remote
git remote add upstream https://github.com/ChrisB0-2/storage-sage.git

# Verify remotes
git remote -v
```

### Build the Project

```bash
# Install dependencies
go mod download

# Build daemon
go build -o storage-sage ./cmd/storage-sage

# Build query tool
go build -o storage-sage-query ./cmd/storage-sage-query

# Run tests
go test ./...
```

### Run Locally

```bash
# Create test configuration
cp test-config.yaml my-config.yaml

# Edit paths to test on your system
vim my-config.yaml

# Run in dry-run mode
./storage-sage --config my-config.yaml --dry-run --once

# Run web backend (optional)
cd web/backend
JWT_SECRET="test-secret" go run .
```

## Making Changes

### Branching Strategy

```bash
# Create a feature branch from main
git checkout main
git pull upstream main
git checkout -b feature/your-feature-name

# Or for bug fixes
git checkout -b fix/issue-number-description
```

### Branch Naming

- Features: `feature/descriptive-name`
- Bug fixes: `fix/issue-number-description`
- Documentation: `docs/what-you-are-documenting`
- Refactoring: `refactor/what-you-are-refactoring`

### Development Workflow

1. Make your changes in your feature branch
2. Write or update tests
3. Update documentation if needed
4. Run tests locally
5. Commit your changes
6. Push to your fork
7. Open a pull request

## Testing

### Run Unit Tests

```bash
# Run all tests
go test ./...

# Run tests with coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Run specific package tests
go test ./internal/cleanup/...

# Run with race detection
go test -race ./...

# Verbose output
go test -v ./...
```

### Run Integration Tests

```bash
# Integration tests (requires Docker)
go test -tags=integration ./...

# End-to-end tests
make test

# Test Docker build
docker-compose build
docker-compose up -d
docker-compose logs -f
```

### Testing Checklist

- [ ] All unit tests pass
- [ ] No race conditions detected
- [ ] Coverage doesn't decrease
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing performed
- [ ] Documentation updated

## Submitting Changes

### Pull Request Process

1. **Update your branch**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

3. **Create Pull Request**
   - Go to GitHub and create a PR from your branch
   - Use the PR template
   - Link related issues
   - Provide clear description

4. **Address Review Comments**
   - Make requested changes
   - Push updates to the same branch
   - Respond to comments

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing performed

## Checklist
- [ ] Code follows project style
- [ ] Documentation updated
- [ ] Tests pass
- [ ] No new warnings
- [ ] Commit messages follow convention

## Related Issues
Fixes #issue_number
```

## Code Style

### Go Code Style

Follow standard Go conventions:

```bash
# Format code
go fmt ./...

# Run linter
golangci-lint run

# Check for common issues
go vet ./...
```

### Style Guidelines

- Use `gofmt` for formatting
- Follow [Effective Go](https://golang.org/doc/effective_go.html)
- Keep functions small and focused
- Write clear variable names
- Add comments for exported functions
- Use meaningful package names

### Example

```go
// Good
func CleanupOldFiles(path string, days int) error {
    files, err := findOldFiles(path, days)
    if err != nil {
        return fmt.Errorf("finding old files: %w", err)
    }
    return deleteFiles(files)
}

// Bad
func clean(p string, d int) error {
    f, e := find(p, d)
    if e != nil {
        return e
    }
    return del(f)
}
```

### Documentation

- Add godoc comments for exported types and functions
- Include examples in documentation
- Keep README and docs up to date

```go
// DeleteOldFiles removes files older than the specified age from the given path.
// It returns the number of files deleted and any error encountered.
//
// Example:
//   count, err := DeleteOldFiles("/tmp/cache", 7)
//   if err != nil {
//       log.Fatal(err)
//   }
//   fmt.Printf("Deleted %d files\n", count)
func DeleteOldFiles(path string, ageDays int) (int, error) {
    // Implementation
}
```

## Commit Messages

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting changes
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

### Examples

```
feat(cleanup): add support for size-based deletion

Add new configuration option to delete files based on size
threshold in addition to age-based deletion.

Closes #123
```

```
fix(metrics): correct byte count calculation

The bytes_freed_total metric was incorrectly counting directory
sizes. This fix ensures only file sizes are counted.

Fixes #456
```

```
docs(readme): update installation instructions

- Add Docker Compose installation steps
- Update system requirements
- Add troubleshooting section
```

### Commit Guidelines

- Use present tense ("add feature" not "added feature")
- Use imperative mood ("move cursor" not "moves cursor")
- Keep subject line under 50 characters
- Separate subject from body with blank line
- Wrap body at 72 characters
- Reference issues and PRs in footer

## Review Process

### What Reviewers Look For

- **Functionality**: Does it work as intended?
- **Tests**: Are there adequate tests?
- **Code Quality**: Is it readable and maintainable?
- **Performance**: Are there performance concerns?
- **Security**: Are there security implications?
- **Documentation**: Is it well documented?

### Review Timeline

- Initial review: Within 2-3 days
- Follow-up reviews: Within 1-2 days
- Approval requires 1-2 maintainer approvals

### After Approval

- Maintainer will merge your PR
- Delete your feature branch
- PR will be included in next release

## Development Tips

### Useful Commands

```bash
# Run daemon with verbose logging
go run ./cmd/storage-sage --config test-config.yaml --dry-run --once

# Watch for changes and rebuild
while true; do inotifywait -r -e modify ./cmd ./internal && go build ./cmd/storage-sage; done

# Check for security issues
gosec ./...

# Profile performance
go test -cpuprofile=cpu.prof -bench=.
go tool pprof cpu.prof
```

### Debugging

```bash
# Run with delve debugger
dlv debug ./cmd/storage-sage -- --config test-config.yaml

# Add debug logging
import "log"
log.Printf("DEBUG: variable value: %+v", variable)
```

### Common Issues

**CGO errors**: Make sure you have SQLite dev libraries
```bash
# Ubuntu/Debian
sudo apt-get install libsqlite3-dev

# macOS
brew install sqlite3
```

**Module issues**: Clear module cache
```bash
go clean -modcache
go mod download
```

## Questions?

- Open an [issue](https://github.com/ChrisB0-2/storage-sage/issues/new)
- Start a [discussion](https://github.com/ChrisB0-2/storage-sage/discussions)
- Contact maintainers

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors will be recognized in:
- Release notes
- CONTRIBUTORS.md file
- Project documentation

Thank you for contributing to StorageSage!
