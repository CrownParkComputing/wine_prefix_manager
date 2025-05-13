#!/bin/bash

# Wine Prefix Manager Build and Release Script
# Handles debug/release builds, version management, and GitHub releases

set -e  # Exit on error

# Display usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --debug                Build debug version"
    echo "  --release              Build release version (default)"
    echo "  --increment TYPE       Increment version number (major, minor, patch)"
    echo "  --release-type TYPE    Set release type (major, minor, patch)"
    echo "  --skip-git             Skip git operations"
    echo "  --distro DISTRO        Build package for specific distro"
    echo "                         Supported: arch, debian, ubuntu, rpm, all"
    echo "                         'all' will build packages for all distros"
    echo "  --help                 Display this help message"
}

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_usage
    exit 0
fi

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
BUILD_ALL_PACKAGES=false
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
                "arch"|"debian"|"ubuntu"|"rpm"|"all")
                    if [ "$DISTRO" = "all" ]; then
                        BUILD_ALL_PACKAGES=true
                    fi
                    ;;
                *)
                    echo "Error: Unsupported distro '$DISTRO'. Supported distros: arch, debian, ubuntu, rpm, all"
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

# Initialize package creation status variables
DEB_CREATED=false
RPM_CREATED=false

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

# Source code archive generation removed - Git already handles version control

# Create PKGBUILD for Arch Linux
if [ "$DISTRO" = "arch" ] || [ "$BUILD_ALL_PACKAGES" = true ]; then
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

# Create Debian package
if [ "$DISTRO" = "debian" ] || [ "$DISTRO" = "ubuntu" ] || [ "$BUILD_ALL_PACKAGES" = true ]; then
    echo "Creating Debian package..."
    
    # Check if necessary tools are installed
    if ! command -v dpkg-deb &> /dev/null; then
        echo "Warning: dpkg-deb not found. Skipping Debian package creation."
        DEB_CREATED=false
    else
    
    # Define Debian package directory structure
    DEB_NAME="${APP_NAME}_${VERSION}-1_amd64"
    DEB_DIR="${RELEASE_DIR}/${DEB_NAME}"
    mkdir -p "${DEB_DIR}/DEBIAN"
    mkdir -p "${DEB_DIR}/usr/bin"
    mkdir -p "${DEB_DIR}/usr/lib/${APP_NAME}"
    mkdir -p "${DEB_DIR}/usr/share/applications"
    mkdir -p "${DEB_DIR}/usr/share/icons/hicolor/128x128/apps"
    
    # Create control file
    cat > "${DEB_DIR}/DEBIAN/control" <<EOF
Package: ${APP_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Depends: wine
Maintainer: Your Name <your.email@example.com>
Description: Wine Prefix Manager
 A tool for managing Wine prefixes on Linux.
EOF
    
    # Extract the application files
    tar -xzf "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz" -C "${RELEASE_DIR}"
    
    # Copy application files to the package directory
    cp -r "${PACKAGE_DIR}"/* "${DEB_DIR}/usr/lib/${APP_NAME}/"
    
    # Create launcher script
    cat > "${DEB_DIR}/usr/bin/${APP_NAME}" <<EOF
#!/bin/bash
exec /usr/lib/${APP_NAME}/${APP_NAME} "\$@"
EOF
    chmod +x "${DEB_DIR}/usr/bin/${APP_NAME}"
    
    # Create desktop entry
    cat > "${DEB_DIR}/usr/share/applications/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Type=Application
Categories=Utility;
EOF
    
    # Copy icon (assuming it exists in the bundle)
    if [ -f "${PACKAGE_DIR}/data/flutter_assets/assets/icon.png" ]; then
        cp "${PACKAGE_DIR}/data/flutter_assets/assets/icon.png" "${DEB_DIR}/usr/share/icons/hicolor/128x128/apps/${APP_NAME}.png"
    fi
    
    # Build the Debian package
    dpkg-deb --build "${DEB_DIR}" "${RELEASE_DIR}/${DEB_NAME}.deb"
    
    # Create checksum
    sha256sum "${RELEASE_DIR}/${DEB_NAME}.deb" > "${RELEASE_DIR}/${DEB_NAME}.deb.sha256"
    
    echo "Debian package created at: ${RELEASE_DIR}/${DEB_NAME}.deb"
    DEB_CREATED=true
    fi
fi

# Create RPM package
if [ "$DISTRO" = "rpm" ] || [ "$BUILD_ALL_PACKAGES" = true ]; then
    echo "Creating RPM package..."
    
    # Check if necessary tools are installed
    if ! command -v rpmbuild &> /dev/null; then
        echo "Warning: rpmbuild not found. Skipping RPM package creation."
        RPM_CREATED=false
    else
    
    # Create RPM build directories
    RPM_BUILD_DIR="${RELEASE_DIR}/rpmbuild"
    mkdir -p "${RPM_BUILD_DIR}/SOURCES"
    mkdir -p "${RPM_BUILD_DIR}/SPECS"
    mkdir -p "${RPM_BUILD_DIR}/BUILD"
    mkdir -p "${RPM_BUILD_DIR}/RPMS"
    mkdir -p "${RPM_BUILD_DIR}/SRPMS"
    
    # Copy the source tarball
    cp "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz" "${RPM_BUILD_DIR}/SOURCES/"
    
    # Create spec file
    cat > "${RPM_BUILD_DIR}/SPECS/${APP_NAME}.spec" <<EOF
Name:           ${APP_NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Wine Prefix Manager
License:        MIT
URL:            https://github.com/jon/wine_prefix_manager
Source0:        ${APP_NAME}-${VERSION}-linux-x64-release.tar.gz
BuildArch:      x86_64
Requires:       wine

%description
A tool for managing Wine prefixes on Linux.

%prep
%setup -q -n ${APP_NAME}-${VERSION}-linux-x64-release

%build
# Nothing to build

%install
mkdir -p %{buildroot}/usr/lib/${APP_NAME}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/128x128/apps

# Copy application files
cp -r * %{buildroot}/usr/lib/${APP_NAME}/

# Create launcher script
cat > %{buildroot}/usr/bin/${APP_NAME} <<EOL
#!/bin/bash
exec /usr/lib/${APP_NAME}/${APP_NAME} "\$@"
EOL
chmod +x %{buildroot}/usr/bin/${APP_NAME}

# Create desktop entry
cat > %{buildroot}/usr/share/applications/${APP_NAME}.desktop <<EOL
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Type=Application
Categories=Utility;
EOL

# Copy icon (assuming it exists in the bundle)
if [ -f "data/flutter_assets/assets/icon.png" ]; then
    cp data/flutter_assets/assets/icon.png %{buildroot}/usr/share/icons/hicolor/128x128/apps/${APP_NAME}.png
fi

%files
/usr/lib/${APP_NAME}
/usr/bin/${APP_NAME}
/usr/share/applications/${APP_NAME}.desktop
/usr/share/icons/hicolor/128x128/apps/${APP_NAME}.png

%changelog
* $(date '+%a %b %d %Y') Your Name <your.email@example.com> - ${VERSION}-1
- Release ${VERSION}
EOF
    
    # Build the RPM package
    rpmbuild --define "_topdir ${RPM_BUILD_DIR}" -bb "${RPM_BUILD_DIR}/SPECS/${APP_NAME}.spec"
    
    # Move the RPM to the release directory
    find "${RPM_BUILD_DIR}/RPMS" -name "*.rpm" -exec cp {} "${RELEASE_DIR}/" \;
    RPM_FILE=$(find "${RELEASE_DIR}" -name "*.rpm" -printf "%f\n")
    
    # Create checksum
    sha256sum "${RELEASE_DIR}/${RPM_FILE}" > "${RELEASE_DIR}/${RPM_FILE}.sha256"
    
    echo "RPM package created at: ${RELEASE_DIR}/${RPM_FILE}"
    RPM_CREATED=true
    fi
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
    
    # Build the list of files to upload
    UPLOAD_FILES=("${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz" 
                  "${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz.sha256")
    
    # Add Debian package if it was created
    if [ "$DEB_CREATED" = true ]; then
        DEB_FILE=$(find "${RELEASE_DIR}" -name "*.deb" -printf "%p\n")
        DEB_CHECKSUM=$(find "${RELEASE_DIR}" -name "*.deb.sha256" -printf "%p\n")
        if [ -n "$DEB_FILE" ]; then
            UPLOAD_FILES+=("$DEB_FILE" "$DEB_CHECKSUM")
        fi
    fi
    
    # Add RPM package if it was created
    if [ "$RPM_CREATED" = true ]; then
        RPM_FILE=$(find "${RELEASE_DIR}" -name "*.rpm" -printf "%p\n")
        RPM_CHECKSUM=$(find "${RELEASE_DIR}" -name "*.rpm.sha256" -printf "%p\n")
        if [ -n "$RPM_FILE" ]; then
            UPLOAD_FILES+=("$RPM_FILE" "$RPM_CHECKSUM")
        fi
    fi
    
    # Add PKGBUILD if it exists
    if [ -f "${RELEASE_DIR}/${APP_NAME}.PKGBUILD" ]; then
        UPLOAD_FILES+=("${RELEASE_DIR}/${APP_NAME}.PKGBUILD")
    fi
    
    # Create the release with all available files
    gh release create "v${VERSION}" \
        ${UPLOAD_FILES[@]} \
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
