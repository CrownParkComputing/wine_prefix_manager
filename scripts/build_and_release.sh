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
# Ensure version is properly formatted by removing any non-semver characters
VERSION=$(echo "$VERSION" | sed 's/[^0-9.]+//g')
# Remove any '+' characters to handle pre-release versions correctly
VERSION=${VERSION//+/}

# Parse arguments
BUILD_TYPE="release"
SKIP_GIT=false
DISTRO="arch"
RELEASE_TYPE=""
INCREMENT="patch"

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
        --distro)
            DISTRO="$2"
            shift 2
            # Validate distro
            case "$DISTRO" in
                "arch"|"debian"|"ubuntu")
                    ;;
                *)
                    echo "Error: Unsupported distro '$DISTRO'. Supported distros: arch, debian, ubuntu"
                    exit 1
                    ;;
            esac
            ;;
        --release-type)
            RELEASE_TYPE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Prompt for release type if not specified
if [ -z "$RELEASE_TYPE" ]; then
    echo "Choose release type (major, minor, patch):"
    read -r RELEASE_TYPE
    echo
fi

# Map release type to increment type
case "$RELEASE_TYPE" in
    major)
        INCREMENT="major"
        ;;
    minor)
        INCREMENT="minor"
        ;;
    patch)
        INCREMENT="patch"
        ;;
    *)
        echo "Invalid release type: $RELEASE_TYPE. Valid options: major, minor, patch"
        exit 1
        ;;
esac

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
    echo "Increment version from $VERSION to $NEW_VERSION? (y/n) "
    read -n 1 -r REPLY
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        VERSION=$NEW_VERSION
        # Update pubspec.yaml version
        sed -i "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
        echo "Version updated to $NEW_VERSION in pubspec.yaml"
    fi
fi

echo "Building Wine Prefix Manager v${VERSION} (${BUILD_TYPE})..."

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean
rm -rf "$RELEASE_DIR"

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

# Create PKGBUILD for Arch Linux
if [ "$DISTRO" = "arch" ]; then
    PKGBUILD_PATH="${RELEASE_DIR}/${APP_NAME}.PKGBUILD"
    echo "Creating PKGBUILD for Arch Linux..."
    
    cat > "$PKGBUILD_PATH" <<EOF
# Maintainer: Your Name <your.email@example.com>
pkgname=${APP_NAME}
pkgver=${VERSION}
pkgrel=1
pkgdesc="Wine Prefix Manager"
arch=(x86_64)
url="https://github.com/jon/wine_prefix_manager"
license=(MIT)
depends=(wine)
source=("${APP_NAME}-${VERSION}-linux-x64-release.tar.gz::https://github.com/jon/wine_prefix_manager/releases/latest/download/${APP_NAME}-${VERSION}-linux-x64-release.tar.gz")
sha256sums=(\$(sha256sum "${RELEASE_DIR}/${APP_NAME}-${VERSION}-linux-x64-release.tar.gz" | awk '{print $1}'))

build() {
    mkdir -p build
    tar -xzf "${SOURCE}" -C build
    cd build
    # Add any additional build steps if needed
}

package() {
    cd build
    make DESTDIR="\$pkgdir/" install
}
EOF

    echo "PKGBUILD created at: $PKGBUILD_PATH"
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
    # Try to get release notes from git commit history
    RELEASE_NOTES=$(git log --format="* %s" $(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo HEAD~10)..HEAD)
    # If no release notes, use a simple placeholder
    if [ -z "$RELEASE_NOTES" ]; then
        RELEASE_NOTES="Release version $VERSION"
    fi
    
    gh release create "v${VERSION}" \
        "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz" \
        "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz.sha256" \
        "${SOURCE_ZIP}" \
        --title "v${VERSION}" \
        --notes "$RELEASE_NOTES"
    
    # Verify and sync versions after release
    echo "Verifying version consistency..."
    PUBSPEC_VERSION=$(grep 'version:' pubspec.yaml | awk '{print $2}' | tr -d "'\"")
    GIT_TAG_VERSION=$(git describe --tags --abbrev=0 | sed 's/^v//')

    if [ "$PUBSPEC_VERSION" != "$GIT_TAG_VERSION" ]; then
        echo "Version mismatch detected. Syncing pubspec.yaml with git tag..."
        sed -i "s/^version: .*/version: $GIT_TAG_VERSION/" pubspec.yaml
        git add pubspec.yaml
        git commit -m "chore: sync pubspec version with git tag ($GIT_TAG_VERSION)"
        git push origin main
        echo "Version synchronized successfully"
    else
        echo "Versions are in sync. No changes needed."
    fi

    echo "Final version check:"
    FINAL_PUBSPEC_VERSION=$(grep 'version:' pubspec.yaml | awk '{print $2}' | tr -d "'\"")
    FINAL_GIT_VERSION=$(git describe --tags --abbrev=0 | sed 's/^v//')
    echo "Git tag: v$FINAL_GIT_VERSION"
    echo "Pubspec: $FINAL_PUBSPEC_VERSION"
fi

echo "Build and release complete! 🎉"
