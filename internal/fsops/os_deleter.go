package fsops

import "os"

// OSDeleter implements Deleter using real os package calls
type OSDeleter struct{}

func (OSDeleter) Remove(path string) error {
	return os.Remove(path)
}

func (OSDeleter) RemoveAll(path string) error {
	return os.RemoveAll(path)
}
