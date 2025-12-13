package fsops

// Deleter abstracts filesystem delete operations
// Enables mocking in tests to prove dry-run never deletes
type Deleter interface {
	Remove(path string) error
	RemoveAll(path string) error
}
