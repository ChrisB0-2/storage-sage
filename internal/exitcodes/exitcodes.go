package exitcodes

// Exit codes for StorageSage daemon
// These codes form the operational contract with CI/CD and operators
const (
	Success         = 0 // Successful execution
	InvalidConfig   = 2 // Configuration file invalid or missing
	SafetyViolation = 3 // Safety validator blocked an operation
	RuntimeError    = 4 // Runtime error during execution
)
