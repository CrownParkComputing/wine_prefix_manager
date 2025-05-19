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
    echo "  --skip-git        # Build AppImage with multiple fallback options
    set +e
    
    # Set architecture explicitly
    export ARCH="x86_64"
    
    # First try with our strip wrapper
    ./appimagetool AppDir "$APPIMAGE_NAME"
    RESULT=$?
    
    # If that fails, try with APPIMAGE_EXTRACT_AND_RUN to avoid FUSE issues
    if [ $RESULT -ne 0 ]; then
      echo "First attempt failed, trying with APPIMAGE_EXTRACT_AND_RUN=1..."
      export APPIMAGE_EXTRACT_AND_RUN=1
      ./appimagetool AppDir "$APPIMAGE_NAME" 
      RESULT=$?
    figit operations"
    echo "  --distro DISTRO        Build package for specific distro"
    echo "                         Supported: arch, debian, ubuntu, rpm, appimage, all"
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
                "arch"|"debian"|"ubuntu"|"rpm"|"appimage"|"all")
                    if [ "$DISTRO" = "all" ]; then
                        BUILD_ALL_PACKAGES=true
                    fi
                    ;;
                *)
                    echo "Error: Unsupported distro '$DISTRO'. Supported distros: arch, debian, ubuntu, rpm, appimage, all"
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

# Create AppImage
if [ "$DISTRO" = "appimage" ] || [ "$BUILD_ALL_PACKAGES" = true ]; then
    echo "Creating AppImage package..."
    
    # Check if necessary tools are installed
    if ! command -v wget &> /dev/null; then
        echo "Warning: wget not found. Skipping AppImage creation."
        APPIMAGE_CREATED=false
    else
        # Install required dependencies
        echo "Installing required dependencies for AppImage..."
        if command -v apt-get &> /dev/null; then
            sudo -n apt-get update || echo "Skipping apt-get update - may need sudo privileges"
            sudo -n apt-get install -y libfuse2 libgtk-3-0 libcurl4 libblkid1 liblzma5 imagemagick || echo "Skipping dependency installation - may need sudo privileges"
        elif command -v pacman &> /dev/null; then
            sudo -n pacman -Sy --noconfirm fuse2 gtk3 imagemagick || echo "Skipping dependency installation - may need sudo privileges"
        fi
        echo "Note: If the AppImage build fails, you may need to manually install dependencies with:"
        echo "  sudo apt-get install libfuse2 libgtk-3-0 libcurl4 libblkid1 liblzma5 imagemagick (on Debian/Ubuntu)"
        echo "  or"
        echo "  sudo pacman -Sy fuse2 gtk3 imagemagick (on Arch Linux)"
    
    # Create directories for AppImage
    APPDIR="${RELEASE_DIR}/AppDir"
    mkdir -p "${APPDIR}/usr/bin"
    mkdir -p "${APPDIR}/usr/lib/${APP_NAME}"
    mkdir -p "${APPDIR}/usr/share/applications"
    mkdir -p "${APPDIR}/usr/share/icons/hicolor/128x128/apps"
    mkdir -p "${APPDIR}/usr/share/metainfo"
    
    # Copy application files
    cp -r "${PACKAGE_DIR}"/* "${APPDIR}/usr/lib/${APP_NAME}/"
    
    # Create launcher script
    cat > "${APPDIR}/usr/bin/${APP_NAME}" <<EOF
#!/bin/bash
exec /usr/lib/${APP_NAME}/${APP_NAME} "\$@"
EOF
    chmod +x "${APPDIR}/usr/bin/${APP_NAME}"
    
    # Create desktop entry
    cat > "${APPDIR}/usr/share/applications/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Type=Application
Categories=Utility;
EOF
    
    # Copy icon
    if [ -f "${PACKAGE_DIR}/data/flutter_assets/assets/icon.png" ]; then
        mkdir -p "${APPDIR}/usr/share/icons/hicolor/128x128/apps/"
        cp "${PACKAGE_DIR}/data/flutter_assets/assets/icon.png" "${APPDIR}/usr/share/icons/hicolor/128x128/apps/${APP_NAME}.png"
    fi
    
    # Create AppRun script
    cat > "${APPDIR}/AppRun" <<EOF
#!/bin/bash
SELF=\$(readlink -f "\$0")
HERE=\${SELF%/*}
export PATH="\${HERE}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${LD_LIBRARY_PATH}"
exec "\${HERE}/usr/bin/${APP_NAME}" "\$@"
EOF
    chmod +x "${APPDIR}/AppRun"
    
    # Create symlinks for icon and desktop file
    ln -sf "./usr/share/icons/hicolor/128x128/apps/${APP_NAME}.png" "${APPDIR}/${APP_NAME}.png"
    ln -sf "./usr/share/applications/${APP_NAME}.desktop" "${APPDIR}/${APP_NAME}.desktop"
    
    # Create appdata file
    cat > "${APPDIR}/usr/share/metainfo/${APP_NAME}.appdata.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${APP_NAME}</id>
  <name>Wine Prefix Manager</name>
  <summary>Manage Wine prefixes on Linux</summary>
  <description>
    <p>A user-friendly tool for managing Wine and Proton prefixes on Linux.</p>
  </description>
  <url type="homepage">https://github.com/jon/wine_prefix_manager</url>
  <launchable type="desktop-id">${APP_NAME}.desktop</launchable>
  <releases>
    <release version="${VERSION}" date="$(date '+%Y-%m-%d')"/>
  </releases>
</component>
EOF
    
    # Download linuxdeploy tool if not present
    if [ ! -f "${RELEASE_DIR}/linuxdeploy-x86_64.AppImage" ]; then
        echo "Downloading linuxdeploy tool..."
        wget -O "${RELEASE_DIR}/linuxdeploy-x86_64.AppImage" "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
        chmod +x "${RELEASE_DIR}/linuxdeploy-x86_64.AppImage"
    fi
    
    # Build AppImage
    APPIMAGE_NAME="${APP_NAME}-${VERSION}-x86_64.AppImage"
    cd "${RELEASE_DIR}"
    echo "Building AppImage..."
    
    # Create a wrapper for strip to handle .relr.dyn sections
    mkdir -p wrapper
    cat > wrapper/strip << 'EOF'
#!/bin/bash

# Get the real strip command
REAL_STRIP=$(which -a strip | grep -v "$(pwd)/wrapper" | head -n1)

# Process all arguments
args=()
for arg in "$@"; do
  if [[ -f "$arg" ]]; then
    # Check if file has .relr.dyn section
    if readelf -S "$arg" 2>/dev/null | grep -q '\.relr\.dyn'; then
      echo "Skipping strip for $arg (contains .relr.dyn section)"
      continue
    fi
  fi
  args+=("$arg")
done

# Only call strip if we have arguments left
if [ ${#args[@]} -gt 0 ]; then
  "$REAL_STRIP" "${args[@]}"
fi
EOF
    chmod +x wrapper/strip
    export PATH="$(pwd)/wrapper:$PATH"
    
    # Download appimagetool instead of using linuxdeploy
    echo "Downloading appimagetool..."
    if [ ! -f "appimagetool" ]; then
      wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O appimagetool
      chmod +x appimagetool
    fi
    
    export VERSION="$VERSION"
    
    # Try to build AppImage with multiple fallback options
    set +e
    
    # First try with our strip wrapper
    ./appimagetool AppDir "$APPIMAGE_NAME"
    RESULT=$?
    
    # If that fails, try with APPIMAGE_EXTRACT_AND_RUN to avoid FUSE issues
    if [ $RESULT -ne 0 ]; then
      echo "First attempt failed, trying with APPIMAGE_EXTRACT_AND_RUN=1..."
      export APPIMAGE_EXTRACT_AND_RUN=1
      ./appimagetool AppDir "$APPIMAGE_NAME" 
      RESULT=$?
    fi
    
    # If that still fails, try bundling only essential components
    if [ $RESULT -ne 0 ]; then
      echo "Basic AppImage creation failed, creating minimal AppImage..."
      # Clean AppDir and reconstruct with minimal dependencies
      rm -rf AppDir
      mkdir -p AppDir/usr/{bin,lib/${APP_NAME},share/{applications,icons/hicolor/128x128/apps}}
      
      # Create a simple icon for AppImage
      convert -size 256x256 xc:transparent -fill '#673AB7' -draw 'circle 128,128 128,20' -fill white -font Arial -pointsize 100 -gravity center -draw "text 0,0 'W'" AppDir/${APP_NAME}.png || echo "Could not create icon with ImageMagick, trying a fallback approach"
      
      # Fallback approach if ImageMagick is not available
      if [ ! -f "AppDir/${APP_NAME}.png" ]; then
        echo "Creating a simple PNG file manually"
        # Create a simple 16x16 colored box as PNG
        printf '\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x10\x00\x00\x00\x10\x08\x02\x00\x00\x00\x90\x91\x68\x36\x00\x00\x00\x01\x73\x52\x47\x42\x00\xAE\xCE\x1C\xE9\x00\x00\x00\x30\x49\x44\x41\x54\x38\x11\x63\xF8\x0F\x05\x0C\x0C\x0C\x0C\x44\x00\xA2\x4C\x46\x35\x60\x34\x0C\x46\xC3\x60\x34\x0C\x46\xC3\x60\x34\x0C\x46\xC3\x60\x34\x0C\x46\xC3\x00\x1D\x06\x00\x24\xE5\x04\x88\xFF\xFF\xFF\xFF\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82' > AppDir/${APP_NAME}.png
      fi
      
      # Copy only essential files
      cp -r ../"${PACKAGE_DIR}"/* AppDir/usr/lib/${APP_NAME}/
      
      # Simplified AppRun
      cat > AppDir/AppRun << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/lib/wine_prefix_manager/wine_prefix_manager" "$@"
EOF
      chmod +x AppDir/AppRun
      
      # Create desktop entry
      cat > AppDir/usr/share/applications/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Type=Application
Categories=Utility;
EOF
      
      # Copy icon
      if [ -f "../${PACKAGE_DIR}/data/flutter_assets/assets/icon.png" ]; then
        cp "../${PACKAGE_DIR}/data/flutter_assets/assets/icon.png" AppDir/usr/share/icons/hicolor/128x128/apps/${APP_NAME}.png
      fi
      
      # Create symlinks
      # Copy icon directly to root dir (needed by appimagetool)
      cp AppDir/usr/share/icons/hicolor/128x128/apps/${APP_NAME}.png AppDir/${APP_NAME}.png
      ln -sf usr/share/applications/${APP_NAME}.desktop AppDir/${APP_NAME}.desktop
      
      # Try building again with minimal approach and disable strip
      export NO_STRIP=1
      ./appimagetool AppDir "$APPIMAGE_NAME"
      RESULT=$?
    fi
    
    # If everything else fails, try one final approach with --no-appstream
    if [ $RESULT -ne 0 ]; then
      echo "Trying one last approach with --no-appstream..."
      export ARCH="x86_64"
      export APPIMAGE_EXTRACT_AND_RUN=1
      export NO_STRIP=1
      
      # Try with a simpler approach
      ./appimagetool --no-appstream AppDir "$APPIMAGE_NAME"
      RESULT=$?
    fi
    
    set -e
    
    # Check if AppImage was created successfully
    if [ -f "$APPIMAGE_NAME" ]; then
      sha256sum "${APPIMAGE_NAME}" > "${APPIMAGE_NAME}.sha256"
      echo "AppImage created at: ${RELEASE_DIR}/${APPIMAGE_NAME}"
      APPIMAGE_CREATED=true
    else
      echo "AppImage creation failed."
      APPIMAGE_CREATED=false
    fi
    
    # Go back to root directory
    cd ..
    
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
    # Generate comprehensive release notes
    COMMITS=$(git log --pretty=format:"* %s (%h)" $(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo HEAD~10)..HEAD)
    
    # Create release notes with version and commits
    RELEASE_NOTES=$(cat << EOF
# Wine Prefix Manager v${VERSION}

Released on $(date '+%Y-%m-%d')

## Changes in this version:

${COMMITS}

## Download Options

* **Debian/Ubuntu**: Download the .deb file
* **RPM-based distros**: Download the .rpm file
* **Other Linux distros**: Download the AppImage file
* **Source code**: Download the .tar.gz file
EOF
    )
    
    # If no commit history found, use a simple placeholder
    if [ -z "$COMMITS" ]; then
        RELEASE_NOTES="# Wine Prefix Manager v${VERSION}\n\nReleased on $(date '+%Y-%m-%d')\n\nThis release contains bug fixes and improvements."
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

    # Add AppImage package if it was created
    if [ "$APPIMAGE_CREATED" = true ]; then
        APPIMAGE_FILE=$(find "${RELEASE_DIR}" -name "*.AppImage" -printf "%p\n" | grep -v "linuxdeploy")
        APPIMAGE_CHECKSUM=$(find "${RELEASE_DIR}" -name "*.AppImage.sha256" -printf "%p\n")
        if [ -n "$APPIMAGE_FILE" ]; then
            UPLOAD_FILES+=("$APPIMAGE_FILE" "$APPIMAGE_CHECKSUM")
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
