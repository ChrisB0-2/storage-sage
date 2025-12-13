package safety

import (
	"os"
	"path/filepath"
	"testing"
)

// TestProtectedPathBlocking verifies protected paths are blocked
func TestProtectedPathBlocking(t *testing.T) {
	tests := []struct {
		name     string
		path     string
		expected bool
	}{
		{"root slash", "/", true},
		{"etc", "/etc", true},
		{"etc subdir", "/etc/ssh", true},
		{"bin", "/bin", true},
		{"bin file", "/bin/bash", true},
		{"usr", "/usr", true},
		{"usr local", "/usr/local", true},
		{"boot", "/boot", true},
		{"boot grub", "/boot/grub2", true},
		{"lib", "/lib", true},
		{"lib64", "/lib64", true},
		{"sbin", "/sbin", true},
		{"storagesage config", "/etc/storage-sage", true},
		{"storagesage config file", "/etc/storage-sage/config.yaml", true},
		{"storagesage db", "/var/lib/storage-sage", true},
		{"storagesage db file", "/var/lib/storage-sage/deletions.db", true},
		{"tmp allowed", "/tmp", false},
		{"tmp file", "/tmp/file.txt", false},
		{"var tmp", "/var/tmp", false},
		{"home", "/home", false},
		{"home user", "/home/user", false},
	}

	protected := defaultProtected(nil)

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsProtectedPath(tt.path, protected)
			if result != tt.expected {
				t.Errorf("IsProtectedPath(%s) = %v, expected %v", tt.path, result, tt.expected)
			}
		})
	}
}

// TestAllowedRootEnforcement verifies paths are restricted to allowed roots
func TestAllowedRootEnforcement(t *testing.T) {
	allowed := []string{"/tmp/allowed", "/var/cleanup"}

	tests := []struct {
		name     string
		path     string
		expected bool
	}{
		{"inside allowed tmp", "/tmp/allowed/file.txt", true},
		{"inside allowed var", "/var/cleanup/old.log", true},
		{"allowed root exact", "/tmp/allowed", true},
		{"outside allowed", "/tmp/notallowed/file.txt", false},
		{"parent of allowed", "/tmp", false},
		{"completely different", "/home/user/file.txt", false},
		{"root", "/", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsWithinAllowedRoots(tt.path, allowed)
			if result != tt.expected {
				t.Errorf("IsWithinAllowedRoots(%s) = %v, expected %v", tt.path, result, tt.expected)
			}
		})
	}
}

// TestPathNormalization verifies paths are normalized correctly
func TestPathNormalization(t *testing.T) {
	tests := []struct {
		name        string
		path        string
		expectError bool
	}{
		{"absolute path", "/tmp/file.txt", false},
		{"relative path", "file.txt", false}, // Gets normalized to absolute
		{"path with dots", "/tmp/./file.txt", false},
		{"empty path", "", true},
		{"whitespace only", "   ", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := NormalizePath(tt.path)
			if tt.expectError {
				if err == nil {
					t.Errorf("NormalizePath(%s) expected error, got nil", tt.path)
				}
			} else {
				if err != nil {
					t.Errorf("NormalizePath(%s) unexpected error: %v", tt.path, err)
				}
				if !filepath.IsAbs(result) {
					t.Errorf("NormalizePath(%s) = %s, expected absolute path", tt.path, result)
				}
			}
		})
	}
}

// TestTraversalDetection verifies ".." segments are detected
func TestTraversalDetection(t *testing.T) {
	tests := []struct {
		name     string
		path     string
		expected bool
	}{
		{"normal path", "/tmp/file.txt", false},
		{"dotdot parent", "/tmp/../etc/passwd", true},
		{"dotdot at start", "../etc/passwd", true},
		{"dotdot at end", "/tmp/..", true},
		{"dotdot middle", "/tmp/../var/file", true},
		{"single dot ok", "/tmp/./file", false},
		{"no traversal", "/tmp/normal/path", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DetectTraversal(tt.path)
			if result != tt.expected {
				t.Errorf("DetectTraversal(%s) = %v, expected %v", tt.path, result, tt.expected)
			}
		})
	}
}

// TestSymlinkEscapeDetection verifies symlinks escaping allowed roots are detected
func TestSymlinkEscapeDetection(t *testing.T) {
	// Create temporary test directory structure
	tmpDir := t.TempDir()
	allowedDir := filepath.Join(tmpDir, "allowed")
	outsideDir := filepath.Join(tmpDir, "outside")

	// Create directories
	if err := os.MkdirAll(allowedDir, 0755); err != nil {
		t.Fatalf("Failed to create allowed dir: %v", err)
	}
	if err := os.MkdirAll(outsideDir, 0755); err != nil {
		t.Fatalf("Failed to create outside dir: %v", err)
	}

	// Create a file outside allowed root
	outsideFile := filepath.Join(outsideDir, "target.txt")
	if err := os.WriteFile(outsideFile, []byte("outside"), 0644); err != nil {
		t.Fatalf("Failed to create outside file: %v", err)
	}

	// Create symlink inside allowed root pointing outside
	symlinkPath := filepath.Join(allowedDir, "link_to_outside")
	if err := os.Symlink(outsideFile, symlinkPath); err != nil {
		t.Fatalf("Failed to create symlink: %v", err)
	}

	// Create symlink inside allowed root pointing inside
	insideFile := filepath.Join(allowedDir, "inside.txt")
	if err := os.WriteFile(insideFile, []byte("inside"), 0644); err != nil {
		t.Fatalf("Failed to create inside file: %v", err)
	}
	safeSymlink := filepath.Join(allowedDir, "safe_link")
	if err := os.Symlink(insideFile, safeSymlink); err != nil {
		t.Fatalf("Failed to create safe symlink: %v", err)
	}

	allowed := []string{allowedDir}

	tests := []struct {
		name          string
		path          string
		expectEscape  bool
		expectError   bool
	}{
		{"symlink escapes", symlinkPath, true, false},
		{"symlink stays inside", safeSymlink, false, false},
		{"regular file inside", insideFile, false, false},
		{"nonexistent path", filepath.Join(allowedDir, "nonexistent"), false, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			escaped, err := DetectSymlinkEscape(tt.path, allowed)
			if tt.expectError {
				if err == nil {
					t.Errorf("DetectSymlinkEscape(%s) expected error, got nil", tt.path)
				}
			} else {
				if err != nil {
					t.Errorf("DetectSymlinkEscape(%s) unexpected error: %v", tt.path, err)
				}
				if escaped != tt.expectEscape {
					t.Errorf("DetectSymlinkEscape(%s) = %v, expected %v", tt.path, escaped, tt.expectEscape)
				}
			}
		})
	}
}

// TestValidateDeleteTarget is the integration test for the full safety contract
func TestValidateDeleteTarget(t *testing.T) {
	tmpDir := t.TempDir()
	allowedDir := filepath.Join(tmpDir, "allowed")
	outsideDir := filepath.Join(tmpDir, "outside")

	// Create directories
	if err := os.MkdirAll(allowedDir, 0755); err != nil {
		t.Fatalf("Failed to create allowed dir: %v", err)
	}
	if err := os.MkdirAll(outsideDir, 0755); err != nil {
		t.Fatalf("Failed to create outside dir: %v", err)
	}

	// Create test files
	insideFile := filepath.Join(allowedDir, "delete_me.txt")
	if err := os.WriteFile(insideFile, []byte("test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	outsideFile := filepath.Join(outsideDir, "keep_me.txt")
	if err := os.WriteFile(outsideFile, []byte("keep"), 0644); err != nil {
		t.Fatalf("Failed to create outside file: %v", err)
	}

	// Create escaping symlink
	escapingLink := filepath.Join(allowedDir, "escape_link")
	if err := os.Symlink(outsideFile, escapingLink); err != nil {
		t.Fatalf("Failed to create escaping symlink: %v", err)
	}

	validator := NewValidator([]string{allowedDir}, nil)

	tests := []struct {
		name        string
		path        string
		expectError error
	}{
		{"allowed file", insideFile, nil},
		{"outside allowed", outsideFile, ErrOutsideAllowed},
		{"protected /etc", "/etc/passwd", ErrProtectedPath},
		{"protected /bin", "/bin/sh", ErrProtectedPath},
		{"protected root", "/", ErrProtectedPath},
		{"escaping symlink", escapingLink, ErrSymlinkEscape},
		{"traversal attempt", filepath.Join(allowedDir, "../outside/keep_me.txt"), ErrTraversal},
		{"empty path", "", ErrInvalidPath},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validator.ValidateDeleteTarget(tt.path)
			if tt.expectError == nil {
				if err != nil {
					t.Errorf("ValidateDeleteTarget(%s) unexpected error: %v", tt.path, err)
				}
			} else {
				if err == nil {
					t.Errorf("ValidateDeleteTarget(%s) expected error %v, got nil", tt.path, tt.expectError)
				} else if err != tt.expectError {
					t.Errorf("ValidateDeleteTarget(%s) = %v, expected %v", tt.path, err, tt.expectError)
				}
			}
		})
	}
}

// TestHasPathPrefix verifies the path prefix checking logic
func TestHasPathPrefix(t *testing.T) {
	tests := []struct {
		name     string
		path     string
		prefix   string
		expected bool
	}{
		{"exact match", "/tmp/allowed", "/tmp/allowed", true},
		{"subdirectory", "/tmp/allowed/sub", "/tmp/allowed", true},
		{"not a prefix", "/tmp/other", "/tmp/allowed", false},
		{"partial match", "/tmp/allowedother", "/tmp/allowed", false},
		{"root prefix", "/tmp", "/", true},
		{"slash prefix explicit", "/tmp", "/", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := hasPathPrefix(tt.path, tt.prefix)
			if result != tt.expected {
				t.Errorf("hasPathPrefix(%s, %s) = %v, expected %v", tt.path, tt.prefix, result, tt.expected)
			}
		})
	}
}
