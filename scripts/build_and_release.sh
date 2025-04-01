#!/bin/bash

# Wine Prefix Manager Build and Release Script
# Handles debug/release builds, version management, and GitHub releases

set -e  # Exit on error

# Configuration
APP_NAME="wine_prefix_manager"
RELEASE_DIR="release"
BUILD_DIR="build/linux/x64"
DEBUG_BUNDLE_DIR="${BUILD_DIR}/debug/bundle"
RELEASE_BUNDLE_DIR="${BUILD_DIR}/release/bundle"
GITHUB_REPO="jon/wine_prefix_manager"  # Update with your GitHub repo

# Get current version from pubspec.yaml
VERSION=$(grep 'version:' pubspec.yaml | awk '{print $2}' | tr -d "'")
VERSION=${VERSION//+/-}  # Replace + with - for filename compatibility

# Parse arguments
BUILD_TYPE="release"
INCREMENT="patch"
SKIP_GIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            BUILD_TYPE="debug"
            shift
            ;;
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        --increment)
            INCREMENT="$2"
            shift 2
            ;;
        --skip-git)
            SKIP_GIT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Ensure script is run from project root
if [ ! -f "pubspec.yaml" ]; then
    echo "Error: This script must be run from the project root directory!"
    exit 1
fi

# Version increment function
increment_version() {
    local version=$1
    local increment=$2
    
    IFS='.' read -r major minor patch <<< "$version"
    
    case "$increment" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "Invalid increment type: $increment"
            exit 1
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Confirm version increment
if [ "$SKIP_GIT" = false ]; then
    NEW_VERSION=$(increment_version "$VERSION" "$INCREMENT")
    read -p "Increment version from $VERSION to $NEW_VERSION? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        VERSION=$NEW_VERSION
        # Update pubspec.yaml version
        sed -i "s/version: $VERSION/version: $NEW_VERSION/" pubspec.yaml
    fi
fi

echo "Building Wine Prefix Manager v${VERSION} (${BUILD_TYPE})..."

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Build for Linux
echo "Building Linux ${BUILD_TYPE}..."
if [ "$BUILD_TYPE" = "debug" ]; then
    flutter build linux --debug
    BUNDLE_DIR=$DEBUG_BUNDLE_DIR
else
    flutter build linux --release
    BUNDLE_DIR=$RELEASE_BUNDLE_DIR
fi

# Create release directory
mkdir -p $RELEASE_DIR

# Package the application
echo "Creating application package..."
PACKAGE_NAME="${APP_NAME}-${VERSION}-linux-x64-${BUILD_TYPE}"
PACKAGE_DIR="${RELEASE_DIR}/${PACKAGE_NAME}"

# Create directory structure
mkdir -p $PACKAGE_DIR

# Copy build artifacts
echo "Copying build artifacts..."
# Copy contents of bundle directory, not the directory itself
find "$BUNDLE_DIR" -maxdepth 1 -mindepth 1 -exec cp -r {} "$PACKAGE_DIR/" \;

# Create tarball
echo "Creating tarball..."
tar -czf "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz" -C "${RELEASE_DIR}" "${PACKAGE_NAME}"

# Create checksum
echo "Creating checksums..."
sha256sum "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz" > "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz.sha256"

# Create source code zip
if [ "$SKIP_GIT" = false ]; then
    echo "Creating source code archive..."
    SOURCE_ZIP="${RELEASE_DIR}/${APP_NAME}-${VERSION}-source.zip"
    git archive --format zip --output "$SOURCE_ZIP" HEAD
fi

echo "Build artifacts created in ${RELEASE_DIR}/ directory:"
ls -la $RELEASE_DIR

# GitHub release process
if [ "$SKIP_GIT" = false ]; then
    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        echo "GitHub CLI (gh) not found. Please install it to create releases."
        exit 1
    fi

    # Check if we're in a git repo
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo "Not in a git repository. Skipping GitHub release."
        exit 0
    fi

    # Push changes to GitHub
    echo "Pushing changes to GitHub..."
    git add .
    git commit -m "Release v${VERSION}"
    git tag -a "v${VERSION}" -m "Version ${VERSION}"
    git push origin main
    git push origin "v${VERSION}"

    # Create GitHub release
    echo "Creating GitHub release..."
    RELEASE_NOTES=$(cat CHANGELOG.md | awk -v version="$VERSION" '/^## / {p=0} $0 ~ "^## " version {p=1} p')
    
    gh release create "v${VERSION}" \
        "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz" \
        "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz.sha256" \
        "${SOURCE_ZIP}" \
        --title "v${VERSION}" \
        --notes "$RELEASE_NOTES"
fi

echo "Build and release complete! 🎉"
