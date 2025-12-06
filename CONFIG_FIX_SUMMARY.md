# Config Fix Summary

## Problem
When cloning the repository on a new VM, the config was failing because:
1. `config.yaml` was committed to Git with test paths that don't exist on new VMs
2. `config.yaml.example` had empty `scan_paths: []` which fails validation (daemon requires at least one path)

## Solution Applied

### 1. Updated `.gitignore`
- Added `web/config/config.yaml` to `.gitignore` to prevent committing test-specific configs
- Kept `web/config/config.yaml.example` in the repository

### 2. Updated `config.yaml.example`
- Added a valid default path: `/tmp/storage-sage-test`
- Added clear documentation about requiring at least one path
- Added `database_path` field
- Added commented examples for path-specific rules

### 3. Updated `setup-after-clone.sh`
- Enhanced config creation to verify at least one path exists
- Added warning if config needs paths
- Automatically adds default test path if scan_paths is empty

## Next Steps

### To Remove config.yaml from Git (if it's currently tracked):

```bash
# Check if config.yaml is tracked
git ls-files web/config/config.yaml

# If it shows the file, remove it from Git (but keep locally)
git rm --cached web/config/config.yaml

# Commit the changes
git add .gitignore
git add web/config/config.yaml.example
git add setup-after-clone.sh
git commit -m "Fix: Exclude config.yaml from Git and fix default config

- Add web/config/config.yaml to .gitignore
- Update config.yaml.example with valid default path
- Update setup script to create valid default config
- Prevents config issues when cloning on new VMs"
```

### Testing on New VM

After pushing these changes, test on a new VM:

```bash
# Clone fresh
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Run setup (should now work correctly)
chmod +x setup-after-clone.sh
./setup-after-clone.sh

# Verify config is valid
cat web/config/config.yaml | grep -A 2 scan_paths

# Start services
docker compose up -d
```

## What This Fixes

✅ **Config validation errors** - Example config now has valid default path  
✅ **Test path issues** - config.yaml no longer committed with test paths  
✅ **Empty config errors** - Setup script ensures valid config is created  
✅ **Deployment consistency** - Each deployment gets its own config from example  

## Files Changed

- `.gitignore` - Added config.yaml exclusion
- `web/config/config.yaml.example` - Added valid default path and documentation
- `setup-after-clone.sh` - Enhanced config creation with validation
