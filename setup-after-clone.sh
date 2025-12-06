#!/bin/bash
# StorageSage Post-Clone Setup Script
# Run this script after cloning the repository to fix permissions and setup required files
#
# Usage: ./setup-after-clone.sh

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  StorageSage Post-Clone Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Fix script permissions
echo -e "${GREEN}[1/5]${NC} Fixing script executable permissions..."
find . -name "*.sh" -type f ! -perm +111 -exec chmod +x {} \; 2>/dev/null || true
echo "✓ Scripts are now executable"
echo ""

# Step 2: Create .env from .env.example
echo -e "${GREEN}[2/5]${NC} Setting up environment file..."
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "✓ Created .env from .env.example"
        
        # Generate JWT_SECRET if not already set
        if ! grep -q "JWT_SECRET=.*[a-zA-Z0-9]" .env || grep -q "JWT_SECRET=your-secret-here" .env; then
            if command -v openssl >/dev/null 2>&1; then
                JWT_SECRET=$(openssl rand -base64 32)
                # Update JWT_SECRET in .env
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i '' "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
                else
                    # Linux
                    sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
                fi
                echo "✓ Generated JWT_SECRET"
            else
                echo -e "${YELLOW}⚠ OpenSSL not found. Please set JWT_SECRET manually in .env${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ .env.example not found!${NC}"
        exit 1
    fi
else
    echo "✓ .env already exists"
fi
echo ""

# Step 3: Create JWT secret file for docker-compose
echo -e "${GREEN}[3/5]${NC} Setting up JWT secret file..."
mkdir -p secrets
if [ ! -f secrets/jwt_secret.txt ]; then
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 > secrets/jwt_secret.txt
        chmod 600 secrets/jwt_secret.txt
        echo "✓ Created secrets/jwt_secret.txt"
    else
        echo -e "${YELLOW}⚠ OpenSSL not found. Please create secrets/jwt_secret.txt manually${NC}"
        echo "   Run: openssl rand -base64 32 > secrets/jwt_secret.txt"
    fi
else
    echo "✓ secrets/jwt_secret.txt already exists"
fi
echo ""

# Step 4: Run make setup (creates certs and config)
echo -e "${GREEN}[4/5]${NC} Running make setup (creates certificates and config)..."
if command -v make >/dev/null 2>&1; then
    make setup || {
        echo -e "${YELLOW}⚠ make setup had warnings, but continuing...${NC}"
    }
    echo "✓ Setup complete"
else
    echo -e "${YELLOW}⚠ Make not found. Creating certificates and config manually...${NC}"
    
    # Create certificates
    mkdir -p web/certs
    if [ ! -f web/certs/server.crt ] || [ ! -f web/certs/server.key ]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout web/certs/server.key \
                -out web/certs/server.crt \
                -subj "/CN=localhost" 2>/dev/null
            chmod 600 web/certs/server.key
            chmod 644 web/certs/server.crt
            echo "✓ Created TLS certificates"
        else
            echo -e "${RED}✗ OpenSSL required for certificates${NC}"
        fi
    fi
    
    # Create config
    mkdir -p web/config
    if [ ! -f web/config/config.yaml ]; then
        if [ -f web/config/config.yaml.example ]; then
            cp web/config/config.yaml.example web/config/config.yaml
            # Verify config has at least one path (required for validation)
            if ! grep -q "scan_paths:" web/config/config.yaml || grep -qE "scan_paths:\s*\[\]" web/config/config.yaml; then
                echo -e "${YELLOW}⚠ Warning: config.yaml has empty scan_paths. Adding default test path...${NC}"
                # Add a default test path if scan_paths is empty
                if command -v sed >/dev/null 2>&1; then
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        sed -i '' 's|scan_paths: \[\]|scan_paths:\n  - /tmp/storage-sage-test|' web/config/config.yaml 2>/dev/null || true
                    else
                        sed -i 's|scan_paths: \[\]|scan_paths:\n  - /tmp/storage-sage-test|' web/config/config.yaml 2>/dev/null || true
                    fi
                fi
            fi
            echo "✓ Created config.yaml"
            echo -e "${YELLOW}  Note: Review web/config/config.yaml and add your scan paths${NC}"
        else
            echo -e "${YELLOW}⚠ web/config/config.yaml.example not found${NC}"
        fi
    else
        echo "✓ config.yaml already exists"
    fi
fi
echo ""

# Step 5: Verify setup
echo -e "${GREEN}[5/5]${NC} Verifying setup..."
MISSING_FILES=0

if [ ! -f .env ]; then
    echo -e "${RED}✗ .env missing${NC}"
    MISSING_FILES=$((MISSING_FILES + 1))
fi

if [ ! -f secrets/jwt_secret.txt ]; then
    echo -e "${YELLOW}⚠ secrets/jwt_secret.txt missing (optional if using .env JWT_SECRET)${NC}"
fi

if [ ! -f web/certs/server.crt ] || [ ! -f web/certs/server.key ]; then
    echo -e "${YELLOW}⚠ TLS certificates missing${NC}"
fi

if [ ! -f web/config/config.yaml ]; then
    echo -e "${YELLOW}⚠ web/config/config.yaml missing${NC}"
fi

if [ $MISSING_FILES -eq 0 ]; then
    echo -e "${GREEN}✓ All critical files present${NC}"
else
    echo -e "${YELLOW}⚠ Some files are missing. Check above.${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Review and edit .env if needed"
echo "  2. Review web/config/config.yaml for your paths"
echo "  3. Start services:"
echo "     - Using Make:  make start"
echo "     - Using Docker: docker compose up -d"
echo "     - Using script: ./scripts/quickstart.sh"
echo ""
echo "Access the web UI at: https://localhost:8443"
echo "Default credentials: admin / changeme"
echo ""
