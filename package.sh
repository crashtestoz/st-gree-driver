#!/bin/bash

# SmartThings Gree AC Driver - Package Script
# Creates a driver package for deployment

set -e

DRIVER_NAME="gree-driver"

# Extract version from config.yml name field (format: "Gree AC Driver V1.3.3")
if [ -f "config.yml" ]; then
  VERSION=$(grep -E "^name:" config.yml | sed -E "s/.*V([0-9]+\.[0-9]+\.[0-9]+).*/\1/")
else
  echo "ERROR: config.yml not found"
  exit 1
fi

if [ -z "$VERSION" ]; then
  echo "ERROR: Could not extract version from config.yml"
  exit 1
fi

PACKAGE_FILE="${DRIVER_NAME}-v${VERSION}.tar.gz"

echo "================================================"
echo "Packaging Gree AC Driver v${VERSION}"
echo "================================================"

# Clean previous packages
if [ -f "$PACKAGE_FILE" ]; then
  echo "Removing existing package: $PACKAGE_FILE"
  rm "$PACKAGE_FILE"
fi

# Check required files exist
echo "Checking required files..."
required_files=(
  "src/init.lua"
  "src/gree_protocol.lua"
  "src/device_handler.lua"
  "src/crypto.lua"
  "profiles/gree-ac.yml"
  "config.yml"
)

for file in "${required_files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "ERROR: Required file not found: $file"
    exit 1
  fi
  echo "  ✓ $file"
done

# Create package
echo ""
echo "Creating package..."
tar -czf "$PACKAGE_FILE" \
  src/ \
  profiles/ \
  config.yml \
  README.md

echo ""
echo "================================================"
echo "✓ Package created: $PACKAGE_FILE"
echo "================================================"
echo ""
echo "File size: $(ls -lh "$PACKAGE_FILE" | awk '{print $5}')"
echo ""
echo "Next steps:"
echo "1. Test the package:"
echo "   smartthings edge:drivers:package ./$PACKAGE_FILE"
echo ""
echo "2. Install to hub:"
echo "   smartthings edge:drivers:install"
echo ""
echo "3. View logs:"
echo "   smartthings edge:drivers:log"
echo ""
