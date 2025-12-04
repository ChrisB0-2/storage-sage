package auth

import (
	"errors"
)

var (
	ErrUnauthorized = errors.New("unauthorized: insufficient permissions")
)

// Role definitions
const (
	RoleAdmin    = "admin"
	RoleOperator = "operator"
	RoleViewer   = "viewer"
)

// Permission definitions
const (
	PermissionViewConfig     = "config:read"
	PermissionEditConfig     = "config:write"
	PermissionViewMetrics    = "metrics:read"
	PermissionTriggerCleanup = "cleanup:trigger"
	PermissionViewLogs       = "logs:read"
)

// RolePermissions maps roles to their allowed permissions
var RolePermissions = map[string][]string{
	RoleAdmin: {
		PermissionViewConfig,
		PermissionEditConfig,
		PermissionViewMetrics,
		PermissionTriggerCleanup,
		PermissionViewLogs,
	},
	RoleOperator: {
		PermissionViewConfig,
		PermissionViewMetrics,
		PermissionTriggerCleanup,
		PermissionViewLogs,
	},
	RoleViewer: {
		PermissionViewConfig,
		PermissionViewMetrics,
		PermissionViewLogs,
	},
}

// HasPermission checks if user roles include the required permission
func HasPermission(userRoles []string, requiredPermission string) bool {
	for _, role := range userRoles {
		permissions, exists := RolePermissions[role]
		if !exists {
			continue
		}

		for _, perm := range permissions {
			if perm == requiredPermission {
				return true
			}
		}
	}
	return false
}

// RequirePermission middleware generator for specific permissions
func RequirePermission(permission string) func(*Claims) error {
	return func(claims *Claims) error {
		if !HasPermission(claims.Roles, permission) {
			return ErrUnauthorized
		}
		return nil
	}
}
