package safety

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

var (
	ErrInvalidPath    = errors.New("invalid path")
	ErrProtectedPath  = errors.New("protected path")
	ErrOutsideAllowed = errors.New("outside allowed roots")
	ErrTraversal      = errors.New("path traversal detected")
	ErrSymlinkEscape  = errors.New("symlink escape detected")
)

// Validator enforces the safety contract for all delete operations
type Validator struct {
	AllowedRoots   []string
	ProtectedPaths []string
}

// NewValidator creates a validator with allowed roots and optional additional protected paths
func NewValidator(allowed []string, extraProtected []string) *Validator {
	return &Validator{
		AllowedRoots:   normalizeRoots(allowed),
		ProtectedPaths: defaultProtected(extraProtected),
	}
}

// ValidateDeleteTarget is the single-source-of-truth for delete authorization
// Returns typed error on safety violation
func (v *Validator) ValidateDeleteTarget(path string) error {
	// 1. Normalize path to absolute, cleaned form
	p, err := NormalizePath(path)
	if err != nil {
		return err
	}

	// 2. Block protected paths (system-critical)
	if IsProtectedPath(p, v.ProtectedPaths) {
		return ErrProtectedPath
	}

	// 3. Ensure within allowed roots
	if !IsWithinAllowedRoots(p, v.AllowedRoots) {
		return ErrOutsideAllowed
	}

	// 4. Detect path traversal in raw input
	if DetectTraversal(path) {
		return ErrTraversal
	}

	// 5. Detect symlink escape
	escaped, err := DetectSymlinkEscape(p, v.AllowedRoots)
	if err != nil {
		// If symlink resolution fails (path doesn't exist yet), allow deletion attempt
		// The actual delete will fail if path doesn't exist anyway
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if escaped {
		return ErrSymlinkEscape
	}

	return nil
}

// NormalizePath converts path to absolute, cleaned form
func NormalizePath(path string) (string, error) {
	if strings.TrimSpace(path) == "" {
		return "", ErrInvalidPath
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", ErrInvalidPath
	}
	return filepath.Clean(abs), nil
}

// DetectTraversal blocks any ".." segment in raw input
func DetectTraversal(raw string) bool {
	parts := strings.Split(filepath.ToSlash(raw), "/")
	for _, p := range parts {
		if p == ".." {
			return true
		}
	}
	return false
}

// IsWithinAllowedRoots checks if path is within any allowed root
func IsWithinAllowedRoots(path string, allowedRoots []string) bool {
	p := filepath.Clean(path)
	for _, r := range allowedRoots {
		if hasPathPrefix(p, r) {
			return true
		}
	}
	return false
}

// DetectSymlinkEscape resolves symlinks and checks if resolved path escapes allowed roots
func DetectSymlinkEscape(cleanAbs string, allowedRoots []string) (bool, error) {
	resolved, err := filepath.EvalSymlinks(cleanAbs)
	if err != nil {
		return false, err
	}
	resolvedAbs, err := filepath.Abs(resolved)
	if err != nil {
		return false, err
	}
	resolvedClean := filepath.Clean(resolvedAbs)
	// Only flag as escape if the resolved path is outside allowed roots.
	if !IsWithinAllowedRoots(resolvedClean, allowedRoots) {
		return true, nil
	}
	return false, nil
}

// IsProtectedPath checks if path matches protected system paths
func IsProtectedPath(path string, protected []string) bool {
	p := filepath.Clean(path)

	// Hard block: "/" exact
	if p == string(os.PathSeparator) {
		return true
	}

	for _, prot := range protected {
		prot = filepath.Clean(prot)
		if p == prot || hasPathPrefix(p, prot) {
			return true
		}
	}
	return false
}

// hasPathPrefix checks if path has the given prefix
func hasPathPrefix(path, prefix string) bool {
	path = filepath.Clean(path)
	prefix = filepath.Clean(prefix)

	if prefix == string(os.PathSeparator) {
		return path == "/"
	}
	if path == prefix {
		return true
	}
	return strings.HasPrefix(path, prefix+string(os.PathSeparator))
}

// normalizeRoots converts slice of roots to absolute, cleaned paths
func normalizeRoots(roots []string) []string {
	out := make([]string, 0, len(roots))
	for _, r := range roots {
		if strings.TrimSpace(r) == "" {
			continue
		}
		abs, err := filepath.Abs(r)
		if err != nil {
			continue
		}
		out = append(out, filepath.Clean(abs))
	}
	return out
}

// defaultProtected returns the base set of protected paths plus any extras
func defaultProtected(extra []string) []string {
	base := []string{
		"/",
		"/etc",
		"/bin",
		"/usr",
		"/boot",
		"/lib",
		"/lib64",
		"/sbin",
		"/var/lib/storage-sage",
		"/etc/storage-sage",
	}
	return append(base, extra...)
}
