# Script Fixes for GitHub Repository

## Issues Identified

After pushing storage-sage to GitHub, test and quickstart scripts fail due to:

1. **Missing `.env.example`** - Required by Makefile `setup` target and referenced by quickstart scripts
2. **Script executable permissions** - Scripts lose execute permissions when cloned from Git
3. **Missing setup files** - TLS certificates, JWT secret, and config files are intentionally not in the repo (security)

## Solution

### Quick Fix (Recommended)

Run the post-clone setup script after cloning:

```bash
# After cloning the repository
git clone https://github.com/ChrisB0-2/storage-sage.git
cd storage-sage

# Run the setup script
chmod +x setup-after-clone.sh
./setup-after-clone.sh

# Then start services
docker compose up -d
```

### Manual Fix

If you prefer to do it manually:

```bash
# 1. Make all scripts executable
find . -name "*.sh" -type f -exec chmod +x {} \;

# 2. Create .env from example
cp .env.example .env

# 3. Generate and set JWT_SECRET in .env
# Option A: Using sed (Linux)
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$(openssl rand -base64 32)|" .env
# Option B: Edit manually
nano .env  # Set JWT_SECRET to a random value

# 4. Create JWT secret file for docker-compose
mkdir -p secrets
openssl rand -base64 32 > secrets/jwt_secret.txt
chmod 600 secrets/jwt_secret.txt

# 5. Run make setup (creates certs and config)
make setup

# 6. Start services
docker compose up -d
```

## What the Setup Script Does

The `setup-after-clone.sh` script automates:

1. ✅ Fixes executable permissions on all `.sh` files
2. ✅ Creates `.env` from `.env.example`
3. ✅ Generates a secure JWT_SECRET in `.env`
4. ✅ Creates `secrets/jwt_secret.txt` for docker-compose
5. ✅ Runs `make setup` to create TLS certificates and config.yaml
6. ✅ Verifies all required files are present

## Files Created During Setup

These files are **not** in the repository (by design, for security):

- `.env` - Your local environment configuration (copy from `.env.example`)
- `secrets/jwt_secret.txt` - JWT secret for authentication
- `web/certs/server.crt` - TLS certificate
- `web/certs/server.key` - TLS private key
- `web/config/config.yaml` - Your configuration (copy from `web/config/config.yaml.example`)

## Verification

After running the setup script, verify everything is ready:

```bash
# Check files exist
test -f .env && echo "✓ .env exists" || echo "✗ .env missing"
test -f secrets/jwt_secret.txt && echo "✓ JWT secret exists" || echo "✗ JWT secret missing"
test -f web/certs/server.crt && echo "✓ Certificate exists" || echo "✗ Certificate missing"
test -f web/config/config.yaml && echo "✓ Config exists" || echo "✗ Config missing"

# Check scripts are executable
ls -la *.sh scripts/*.sh | grep -q "^-rwx" && echo "✓ Scripts are executable" || echo "⚠ Some scripts may not be executable"
```

## Common Issues

### Issue: `make setup` fails with "JWT_SECRET not set"

**Solution:** The `.env` file needs a `JWT_SECRET` value. Either:
- Run `./setup-after-clone.sh` which sets it automatically
- Manually edit `.env` and set `JWT_SECRET` to a random value

### Issue: Scripts say "Permission denied"

**Solution:** Make scripts executable:
```bash
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### Issue: `docker-compose up` fails with "jwt_secret file not found"

**Solution:** Create the secret file:
```bash
mkdir -p secrets
openssl rand -base64 32 > secrets/jwt_secret.txt
chmod 600 secrets/jwt_secret.txt
```

## Next Steps

After setup is complete:

1. **Review configuration:**
   ```bash
   nano web/config/config.yaml
   ```
   Set your scan paths and cleanup rules.

2. **Start services:**
   ```bash
   docker compose up -d
   ```

3. **Verify everything works:**
   ```bash
   ./scripts/comprehensive_test.sh
   ```

4. **Access the web UI:**
   - URL: https://localhost:8443
   - Username: `admin`
   - Password: `changeme` (change in production!)

## Repository Files Added

To fix these issues, the following files have been added to the repository:

1. **`.env.example`** - Template for environment variables
2. **`setup-after-clone.sh`** - Automated setup script
3. **`SCRIPT_FIXES.md`** - This documentation file

## Contributing

When contributing, ensure:

1. Scripts have executable permissions (Git will preserve them)
2. Never commit `.env`, `secrets/`, or `web/certs/` to the repository
3. Update `.env.example` if adding new environment variables
4. Test that `setup-after-clone.sh` works after cloning a fresh copy
