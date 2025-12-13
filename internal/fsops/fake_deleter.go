package fsops

// FakeDeleter implements Deleter for testing
// Records all delete calls without performing actual deletions
type FakeDeleter struct {
	Calls []string
}

func (f *FakeDeleter) Remove(path string) error {
	f.Calls = append(f.Calls, "rm:"+path)
	return nil
}

func (f *FakeDeleter) RemoveAll(path string) error {
	f.Calls = append(f.Calls, "rmall:"+path)
	return nil
}
