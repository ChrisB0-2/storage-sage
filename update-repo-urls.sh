#!/bin/bash
# Script to update repository URLs in StorageSage documentation

set -e

echo "=== StorageSage Repository URL Updater ==="
echo ""
echo "Enter your GitHub username:"
read -p "> " GITHUB_USER

if [ -z "$GITHUB_USER" ]; then
    echo "Error: GitHub username cannot be empty"
    exit 1
fi

echo ""
echo "Updating repository URLs to: github.com/$GITHUB_USER/storage-sage"
echo ""

# Update files
for file in README.md INSTALL.md CONTRIBUTING.md QUICK_START.md PACKAGING_SUMMARY.md PRODUCTION_CHECKLIST.md .goreleaser.yaml .github/workflows/ci.yml .github/workflows/release.yml; do
    if [ -f "$file" ]; then
        echo "✓ Updating $file"
        sed -i "s|yourusername/storage-sage|$GITHUB_USER/storage-sage|g" "$file"
        sed -i "s|github.com/yourusername|github.com/$GITHUB_USER|g" "$file"
    fi
done

echo ""
echo "=== Update Complete! ==="
echo ""
echo "Next steps:"
echo "1. Review: git diff"
echo "2. Commit: git add . && git commit -m 'Update repository URLs'"
echo "3. Push: git push origin main"
echo "4. Release: git tag -a v0.9.0 -m 'Initial release' && git push origin v0.9.0"
