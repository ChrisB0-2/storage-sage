#!/bin/bash
# StorageSage Frontend Setup Script

set -e

echo "==================================="
echo "StorageSage Frontend Setup"
echo "==================================="

# Check Node.js version
echo "Checking Node.js version..."
if ! command -v node &> /dev/null; then
    echo "ERROR: Node.js is not installed"
    echo "Please install Node.js >= 16 from https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 16 ]; then
    echo "ERROR: Node.js version must be >= 16 (current: $(node -v))"
    exit 1
fi
echo "✓ Node.js $(node -v)"

# Check npm version
echo "Checking npm version..."
if ! command -v npm &> /dev/null; then
    echo "ERROR: npm is not installed"
    exit 1
fi
echo "✓ npm $(npm -v)"

# Copy .env.example to .env if not exists
if [ ! -f .env ]; then
    echo "Creating .env file..."
    cp .env.example .env
    echo "✓ Created .env (configure API URL if needed)"
else
    echo "✓ .env already exists"
fi

# Install dependencies
echo ""
echo "Installing dependencies..."
npm install

echo ""
echo "==================================="
echo "✓ Setup complete!"
echo "==================================="
echo ""
echo "Next steps:"
echo "  1. Edit .env to configure API URL"
echo "  2. Run 'npm run dev' for development"
echo "  3. Run 'npm run build' for production"
echo ""
