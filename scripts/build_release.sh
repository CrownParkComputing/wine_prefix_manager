#!/bin/bash

# Wine Prefix Manager Release Builder
# This script builds a release version for Linux and creates distributable artifacts

set -e  # Exit on error

VERSION="1.5.0"
APP_NAME="wine_prefix_manager"
RELEASE_DIR="release"
BUILD_DIR="build/linux/x64/release/bundle"

echo "Building Wine Prefix Manager v${VERSION} for Linux..."

# Ensure the script is run from the project root
if [ ! -f "pubspec.yaml" ]; then
    echo "Error: This script must be run from the project root directory!"
    exit 1
fi

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Build for Linux in release mode
echo "Building Linux release..."
flutter build linux --release

# Create release directory
mkdir -p $RELEASE_DIR

# Package the application
echo "Creating application package..."
PACKAGE_NAME="${APP_NAME}-${VERSION}-linux-x64"
PACKAGE_DIR="${RELEASE_DIR}/${PACKAGE_NAME}"

# Create directory structure
mkdir -p $PACKAGE_DIR

# Copy build artifacts
echo "Copying build artifacts..."
cp -r $BUILD_DIR/* $PACKAGE_DIR/

# Create tarball
echo "Creating tarball..."
cd $RELEASE_DIR
tar -czf "${PACKAGE_NAME}.tar.gz" $PACKAGE_NAME
cd ..

# Create AppImage (optional - requires additional tools)
echo "Note: To create an AppImage, additional setup is required."
echo "See https://docs.appimage.org/packaging-guide/overview.html for more information."

# Create checksum
echo "Creating checksums..."
cd $RELEASE_DIR
sha256sum "${PACKAGE_NAME}.tar.gz" > "${PACKAGE_NAME}.tar.gz.sha256"
cd ..

echo "Release artifacts created in ${RELEASE_DIR}/ directory:"
ls -la $RELEASE_DIR

echo "Build complete! 🎉"
