#!/bin/bash

# Wine Prefix Manager - Interactive Menu-Based Script
# This script provides an interactive menu to guide users through various operations

set -e  # Exit on error

# Colors for better readability
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
BOLD="\033[1m"
RESET="\033[0m"

# Configuration
APP_NAME="wine_prefix_manager"
RELEASE_DIR="release"
BUILD_DIR="build/linux/x64"
RELEASE_BUNDLE_DIR="${BUILD_DIR}/release/bundle"
DEBUG_BUNDLE_DIR="${BUILD_DIR}/debug/bundle"
GITHUB_REPO="jon/wine_prefix_manager"  # Update with your GitHub username/repo

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${CYAN}${BOLD}                 WINE PREFIX MANAGER                       ${RESET}"
    echo -e "${BLUE}${BOLD}============================================================${RESET}"
    echo -e "${MAGENTA}Interactive build, release, and management tool${RESET}"
    echo ""
}

# Function to display the main menu
show_main_menu() {
    show_header
    echo -e "${BOLD}MAIN MENU${RESET}"
    echo -e " ${GREEN}1)${RESET} Build Packages"
    echo -e " ${GREEN}2)${RESET} Create Release"
    echo -e " ${GREEN}3)${RESET} Debug and Development"
    echo -e " ${GREEN}4)${RESET} Installation Options"
    echo -e " ${GREEN}5)${RESET} Project Maintenance"
    echo -e " ${GREEN}6)${RESET} System Setup"
    echo -e " ${RED}0)${RESET} Exit"
    echo ""
    echo -e "${YELLOW}Current version:${RESET} $VERSION"
    echo ""
    echo -e "${BLUE}Choose an option:${RESET}"
}

# Function to show build menu
show_build_menu() {
    show_header
    echo -e "${BOLD}BUILD PACKAGES MENU${RESET}"
    echo -e " ${GREEN}1)${RESET} Build All Packages"
    echo -e " ${GREEN}2)${RESET} Build DEB Package"
    echo -e " ${GREEN}3)${RESET} Build RPM Package"
    echo -e " ${GREEN}4)${RESET} Build AppImage"
    echo -e " ${GREEN}5)${RESET} Build Arch Package"
    echo -e " ${RED}0)${RESET} Back to Main Menu"
    echo ""
    echo -e "${BLUE}Choose an option:${RESET}"
}

# Function to show release menu
show_release_menu() {
    show_header
    echo -e "${BOLD}CREATE RELEASE MENU${RESET}"
    echo -e " ${GREEN}1)${RESET} Create Patch Release (${CURRENT_VERSION} → $(increment_version "$VERSION" "patch"))"
    echo -e " ${GREEN}2)${RESET} Create Minor Release (${CURRENT_VERSION} → $(increment_version "$VERSION" "minor"))"
    echo -e " ${GREEN}3)${RESET} Create Major Release (${CURRENT_VERSION} → $(increment_version "$VERSION" "major"))"
    echo -e " ${GREEN}4)${RESET} Create Local-Only Release (No GitHub Push)"
    echo -e " ${RED}0)${RESET} Back to Main Menu"
    echo ""
    echo -e "${BLUE}Choose an option:${RESET}"
}

# Function to show debug menu
show_debug_menu() {
    show_header
    echo -e "${BOLD}DEBUG AND DEVELOPMENT MENU${RESET}"
    echo -e " ${GREEN}1)${RESET} Build and Run Debug Version"
    echo -e " ${GREEN}2)${RESET} Run Existing Debug Build"
    echo -e " ${GREEN}3)${RESET} Build Debug Version Only"
    echo -e " ${GREEN}4)${RESET} Run Flutter Analyze"
    echo -e " ${RED}0)${RESET} Back to Main Menu"
    echo ""
    echo -e "${BLUE}Choose an option:${RESET}"
}

# Function to show installation menu
show_installation_menu() {
    show_header
    echo -e "${BOLD}INSTALLATION OPTIONS MENU${RESET}"
    echo -e " ${GREEN}1)${RESET} Build and Install Locally"
    echo -e " ${GREEN}2)${RESET} Install from Existing Build"
    echo -e " ${RED}0)${RESET} Back to Main Menu"
    echo ""
    echo -e "${BLUE}Choose an option:${RESET}"
}

# Function to show maintenance menu
show_maintenance_menu() {
    show_header
    echo -e "${BOLD}PROJECT MAINTENANCE MENU${RESET}"
    echo -e " ${GREEN}1)${RESET} Clean Build Directories"
    echo -e " ${GREEN}2)${RESET} Run Flutter Analyze"
    echo -e " ${RED}0)${RESET} Back to Main Menu"
    echo ""
    echo -e "${BLUE}Choose an option:${RESET}"
}

# Function to show system setup menu
show_system_setup_menu() {
    show_header
    echo -e "${BOLD}SYSTEM SETUP MENU${RESET}"
    echo -e " ${GREEN}1)${RESET} Install Dependencies (Auto-detect Distribution)"
    echo -e " ${GREEN}2)${RESET} Install Dependencies for Ubuntu/Debian"
    echo -e " ${GREEN}3)${RESET} Install Dependencies for Fedora/RHEL/CentOS"
    echo -e " ${GREEN}4)${RESET} Install Dependencies for Arch/Manjaro"
    echo -e " ${RED}0)${RESET} Back to Main Menu"
    echo ""
    echo -e "${BLUE}Choose an option:${RESET}"
}

# Function to detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID=$ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO_ID=$DISTRIB_ID
    else
        echo -e "${RED}Unable to detect Linux distribution. Please specify with --distro.${RESET}"
        exit 1
    fi
    
    echo -e "${GREEN}Detected distribution: $DISTRO_ID${RESET}"
    DISTRO=${DISTRO_ID,,}  # Convert to lowercase
    return 0
}

# Function to install dependencies
install_dependencies() {
    local distro=$1
    
    echo -e "${BLUE}Installing dependencies for $distro...${RESET}"
    
    case "$distro" in
        ubuntu|debian)
            echo "Installing dependencies for Ubuntu/Debian..."
            sudo apt update
            sudo apt install -y \
                wine \
                zenity \
                zip \
                unzip \
                clang \
                cmake \
                ninja-build \
                pkg-config \
                libgtk-3-dev \
                dpkg-dev \
                fakeroot \
                liblzma-dev \
                libstdc++-12-dev \
                libx11-dev
            ;;
        fedora|rhel|centos)
            echo "Installing dependencies for Fedora/RHEL/CentOS..."
            sudo dnf install -y \
                wine \
                zenity \
                zip \
                unzip \
                clang \
                cmake \
                ninja-build \
                gtk3-devel \
                libstdc++-devel \
                xz-devel \
                libX11-devel \
                rpm-build
            ;;
        arch|manjaro)
            echo "Installing dependencies for Arch/Manjaro..."
            sudo pacman -Sy --needed \
                wine \
                zenity \
                zip \
                unzip \
                clang \
                cmake \
                ninja \
                pkg-config \
                gtk3 \
                lzma \
                libx11
            ;;
        *)
            echo -e "${RED}Unsupported distribution: $distro${RESET}"
            echo "Please install the following packages manually:"
            echo "- wine, zenity, zip, unzip"
            echo "- clang, cmake, ninja-build, pkg-config"
            echo "- GTK3 development libraries"
            echo "- LZMA development libraries"
            echo "- X11 development libraries"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}Dependencies installed successfully!${RESET}"
}

# Function to increment version number
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
            echo -e "${RED}Invalid increment type: $increment${RESET}"
            exit 1
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to build packages
build_packages() {
    local package_type=$1
    local version=$2
    local build_type=$3
    
    # Prepare build directories
    mkdir -p "$RELEASE_DIR"
    
    # Common build setup
    if [ "$build_type" = "debug" ]; then
        echo -e "${YELLOW}Building debug version...${RESET}"
        flutter build linux --debug
        BUNDLE_DIR=$DEBUG_BUNDLE_DIR
    else
        echo -e "${YELLOW}Building release version...${RESET}"
        flutter build linux --release
        BUNDLE_DIR=$RELEASE_BUNDLE_DIR
    fi
    
    # Return early if not building packages (debug mode)
    if [ "$build_type" = "debug" ]; then
        return 0
    fi
    
    local arch_built=false
    local deb_built=false
    local rpm_built=false
    local appimage_built=false
    
    # Process each package type
    case "$package_type" in
        all)
            echo -e "${YELLOW}Building all package types...${RESET}"
            build_arch_package "$version" && arch_built=true
            build_deb_package "$version" && deb_built=true
            build_rpm_package "$version" && rpm_built=true
            build_appimage "$version" && appimage_built=true
            ;;
        arch)
            echo -e "${YELLOW}Building Arch Linux package...${RESET}"
            build_arch_package "$version" && arch_built=true
            ;;
        deb)
            echo -e "${YELLOW}Building Debian package...${RESET}"
            build_deb_package "$version" && deb_built=true
            ;;
        rpm)
            echo -e "${YELLOW}Building RPM package...${RESET}"
            build_rpm_package "$version" && rpm_built=true
            ;;
        appimage)
            echo -e "${YELLOW}Building AppImage...${RESET}"
            build_appimage "$version" && appimage_built=true
            ;;
        *)
            echo -e "${RED}Unsupported package type: $package_type${RESET}"
            echo "Supported types: all, arch, deb, rpm, appimage"
            exit 1
            ;;
    esac
    
    # Show build results
    echo ""
    echo -e "${BLUE}Build Results:${RESET}"
    [ "$arch_built" = true ] && echo -e "${GREEN}✓${RESET} Arch package built successfully" || echo -e "${RED}✗${RESET} Arch package not built"
    [ "$deb_built" = true ] && echo -e "${GREEN}✓${RESET} Debian package built successfully" || echo -e "${RED}✗${RESET} Debian package not built"
    [ "$rpm_built" = true ] && echo -e "${GREEN}✓${RESET} RPM package built successfully" || echo -e "${RED}✗${RESET} RPM package not built"
    [ "$appimage_built" = true ] && echo -e "${GREEN}✓${RESET} AppImage built successfully" || echo -e "${RED}✗${RESET} AppImage not built"
}

# Build Arch Linux package
build_arch_package() {
    local version=$1
    echo "Building Arch Linux package..."
    
    # Create PKGBUILD in release directory
    cp "$APP_NAME.PKGBUILD" "$RELEASE_DIR/PKGBUILD"
    sed -i "s/pkgver=.*/pkgver=$version/" "$RELEASE_DIR/PKGBUILD"
    
    # Build package
    pushd "$RELEASE_DIR" > /dev/null
    makepkg -f
    popd > /dev/null
    
    echo -e "${GREEN}Arch package built: $RELEASE_DIR/${APP_NAME}-${version}-*.pkg.tar.zst${RESET}"
    return 0
}

# Build Debian package
build_deb_package() {
    local version=$1
    echo "Building Debian package..."
    
    # Create Debian package structure
    local DEB_DIR="$RELEASE_DIR/${APP_NAME}_${version}_amd64"
    mkdir -p "$DEB_DIR/DEBIAN"
    mkdir -p "$DEB_DIR/usr/bin"
    mkdir -p "$DEB_DIR/usr/lib/${APP_NAME}"
    mkdir -p "$DEB_DIR/usr/share/applications"
    mkdir -p "$DEB_DIR/usr/share/icons/hicolor/512x512/apps"
    
    # Copy application files
    cp -r "$RELEASE_BUNDLE_DIR"/* "$DEB_DIR/usr/lib/${APP_NAME}/"
    
    # Create launcher script
    echo "#!/bin/sh" > "$DEB_DIR/usr/bin/${APP_NAME}"
    echo "exec /usr/lib/${APP_NAME}/${APP_NAME} \"\$@\"" >> "$DEB_DIR/usr/bin/${APP_NAME}"
    chmod +x "$DEB_DIR/usr/bin/${APP_NAME}"
    
    # Copy desktop file and icon
    cp "${APP_NAME}.desktop" "$DEB_DIR/usr/share/applications/"
    cp "assets/icons/winehero.jpg" "$DEB_DIR/usr/share/icons/hicolor/512x512/apps/${APP_NAME}.jpg"
    
    # Create control file
    cat > "$DEB_DIR/DEBIAN/control" << EOL
Package: ${APP_NAME}
Version: ${version}
Section: utils
Priority: optional
Architecture: amd64
Depends: wine, zenity
Maintainer: Jon <jon@example.com>
Description: Wine Prefix Manager for Linux gaming
 A Flutter application to create and manage Wine prefixes for running
 Windows games and applications on Linux.
EOL
    
    # Build the package
    dpkg-deb --build "$DEB_DIR"
    
    echo -e "${GREEN}Debian package built: ${DEB_DIR}.deb${RESET}"
    return 0
}

# Build RPM package
build_rpm_package() {
    local version=$1
    echo "Building RPM package..."
    
    # Create RPM build directories
    local RPM_BUILD_DIR="$RELEASE_DIR/rpm_build"
    mkdir -p "$RPM_BUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    
    # Create source tarball
    tar -czf "$RPM_BUILD_DIR/SOURCES/${APP_NAME}-${version}.tar.gz" -C "$RELEASE_BUNDLE_DIR" .
    
    # Create spec file
    cat > "$RPM_BUILD_DIR/SPECS/${APP_NAME}.spec" << EOL
Name:           ${APP_NAME}
Version:        ${version}
Release:        1%{?dist}
Summary:        Wine Prefix Manager for Linux gaming
License:        MIT
URL:            https://github.com/${GITHUB_REPO}
Source0:        %{name}-%{version}.tar.gz
Requires:       wine zenity

%description
A Flutter application to create and manage Wine prefixes for running
Windows games and applications on Linux.

%prep
%setup -q

%install
mkdir -p %{buildroot}/usr/lib/%{name}
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/512x512/apps

cp -r . %{buildroot}/usr/lib/%{name}/

# Create launcher script
echo '#!/bin/sh' > %{buildroot}/usr/bin/%{name}
echo 'exec /usr/lib/%{name}/%{name} "\$@"' >> %{buildroot}/usr/bin/%{name}
chmod +x %{buildroot}/usr/bin/%{name}

# Copy desktop file and icon
cp %{_sourcedir}/../../../%{name}.desktop %{buildroot}/usr/share/applications/
cp %{_sourcedir}/../../../assets/icons/winehero.jpg %{buildroot}/usr/share/icons/hicolor/512x512/apps/%{name}.jpg

%files
%{_bindir}/%{name}
/usr/lib/%{name}/
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/512x512/apps/%{name}.jpg

%changelog
* $(date +"%a %b %d %Y") Builder <builder@example.com> - ${version}-1
- Automatic build
EOL
    
    # Build the package
    rpmbuild --define "_topdir $PWD/$RPM_BUILD_DIR" -ba "$RPM_BUILD_DIR/SPECS/${APP_NAME}.spec"
    
    # Copy the resulting RPM file to release directory
    cp "$RPM_BUILD_DIR/RPMS/x86_64/${APP_NAME}-${version}"*.rpm "$RELEASE_DIR/"
    
    echo -e "${GREEN}RPM package built: $RELEASE_DIR/${APP_NAME}-${version}*.rpm${RESET}"
    return 0
}

# Build AppImage
build_appimage() {
    local version=$1
    echo "Building AppImage..."
    
    # Prepare AppDir structure
    local APP_DIR="$RELEASE_DIR/AppDir"
    mkdir -p "$APP_DIR/usr/bin"
    mkdir -p "$APP_DIR/usr/lib"
    mkdir -p "$APP_DIR/usr/share/applications"
    mkdir -p "$APP_DIR/usr/share/icons/hicolor/512x512/apps"
    
    # Copy application files
    cp -r "$RELEASE_BUNDLE_DIR" "$APP_DIR/usr/lib/${APP_NAME}"
    
    # Create launcher script
    cat > "$APP_DIR/usr/bin/${APP_NAME}" << EOL
#!/bin/sh
exec "\$(dirname "\$(dirname "\$0")")/lib/${APP_NAME}/${APP_NAME}" "\$@"
EOL
    chmod +x "$APP_DIR/usr/bin/${APP_NAME}"
    
    # Copy desktop file and icon
    cp "${APP_NAME}.desktop" "$APP_DIR/usr/share/applications/"
    cp "assets/icons/winehero.jpg" "$APP_DIR/usr/share/icons/hicolor/512x512/apps/${APP_NAME}.jpg"
    
    # Create AppRun
    cat > "$APP_DIR/AppRun" << EOL
#!/bin/sh
SELF="\$(readlink -f "\$0")"
HERE="\${SELF%/*}"
export PATH="\${HERE}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${LD_LIBRARY_PATH}"
exec "\${HERE}/usr/bin/${APP_NAME}" "\$@"
EOL
    chmod +x "$APP_DIR/AppRun"
    
    # Copy desktop and icon for AppImage
    cp "${APP_NAME}.desktop" "$APP_DIR/${APP_NAME}.desktop"
    cp "assets/icons/winehero.jpg" "$APP_DIR/${APP_NAME}.jpg"
    
    # Create symlinks
    ln -sf "./usr/share/icons/hicolor/512x512/apps/${APP_NAME}.jpg" "$APP_DIR/.DirIcon"
    
    # Download and prepare appimagetool
    cd "$RELEASE_DIR"
    if [ ! -f "appimagetool" ]; then
        wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
        chmod +x appimagetool
    fi
    
    # Build AppImage with fallback options
    APPIMAGE_NAME="${APP_NAME}-${version}-x86_64.AppImage"
    export ARCH="x86_64"
    
    # First try with standard method
    set +e
    ./appimagetool AppDir "$APPIMAGE_NAME"
    RESULT=$?
    
    # If that fails, try with extract and run to avoid FUSE issues
    if [ $RESULT -ne 0 ]; then
        echo "First attempt failed, trying with APPIMAGE_EXTRACT_AND_RUN=1..."
        export APPIMAGE_EXTRACT_AND_RUN=1
        ./appimagetool AppDir "$APPIMAGE_NAME"
        RESULT=$?
    fi
    set -e
    
    cd ..
    
    # Generate checksum
    cd "$RELEASE_DIR"
    sha256sum "$APPIMAGE_NAME" > "${APPIMAGE_NAME}.sha256"
    cd ..
    
    echo -e "${GREEN}AppImage built: $RELEASE_DIR/${APPIMAGE_NAME}${RESET}"
    return 0
}

# Function to install the application locally
install_local() {
    echo -e "${BLUE}Installing ${APP_NAME} locally...${RESET}"
    
    # Create installation directories
    sudo mkdir -p /usr/local/lib/${APP_NAME}
    sudo mkdir -p /usr/local/bin
    sudo mkdir -p /usr/share/applications
    sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
    
    # Copy application files
    sudo cp -r "$RELEASE_BUNDLE_DIR"/* /usr/local/lib/${APP_NAME}/
    
    # Create launcher script
    sudo bash -c "cat > /usr/local/bin/${APP_NAME}" << EOL
#!/bin/sh
exec /usr/local/lib/${APP_NAME}/${APP_NAME} "\$@"
EOL
    sudo chmod +x /usr/local/bin/${APP_NAME}
    
    # Copy desktop file and icon
    sudo cp "${APP_NAME}.desktop" /usr/share/applications/
    sudo cp "assets/icons/winehero.jpg" /usr/share/icons/hicolor/512x512/apps/${APP_NAME}.jpg
    
    # Update desktop database
    sudo update-desktop-database || true
    
    echo -e "${GREEN}${APP_NAME} installed successfully!${RESET}"
    echo "You can now run it by typing '${APP_NAME}' in the terminal or finding it in your application menu."
}

# Function to clean build directories
clean_build() {
    echo -e "${BLUE}Cleaning build directories...${RESET}"
    flutter clean
    rm -rf "$RELEASE_DIR"
    echo -e "${GREEN}Clean completed!${RESET}"
}

# Function to run flutter analyze
run_analyze() {
    echo -e "${BLUE}Running Flutter analyze...${RESET}"
    
    # Create a temporary analysis options file
    cat > .analyze_temp_options.yaml << EOL
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    invalid_use_of_internal_member: ignore
    missing_required_param: error
    missing_return: error
    must_be_immutable: warning
    sort_child_properties_last: ignore
    deprecated_member_use: ignore
    use_build_context_synchronously: ignore
    unnecessary_null_comparison: ignore
    unused_import: ignore
    unused_field: ignore
    unused_local_variable: ignore
    unused_element: ignore
    unnecessary_import: ignore
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "lib/generated_plugin_registrant.dart"
EOL

    # Run analyze with our temporary options file
    flutter analyze --no-fatal-warnings --options=.analyze_temp_options.yaml
    
    # Check if there are any real errors
    echo ""
    echo -e "${YELLOW}Checking for critical errors only...${RESET}"
    flutter analyze --options=.analyze_temp_options.yaml 2>&1 | grep -v "file_picker" | grep -E "^error" > real_errors.txt || true
    
    if [ -s real_errors.txt ]; then
        echo -e "${RED}Critical errors found in your code:${RESET}"
        cat real_errors.txt
        exit_code=1
    else
        echo -e "${GREEN}No critical issues detected!${RESET}"
        exit_code=0
    fi
    
    # Clean up temp file
    rm -f .analyze_temp_options.yaml real_errors.txt
    
    return $exit_code
}

# Function to create a GitHub release
github_release() {
    local version=$1
    local release_type=$2
    
    echo -e "${BLUE}Creating GitHub release v${version}...${RESET}"
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Error: git is not installed. Please install git to create releases.${RESET}"
        return 1
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo -e "${RED}Error: Not in a git repository. Please run this script from a git repository.${RESET}"
        return 1
    fi
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}Warning: You have uncommitted changes. Committing all changes...${RESET}"
        git add .
        git commit -m "Release v${version}"
    fi
    
    # Create tag and push
    echo "Creating tag v${version}..."
    git tag -a "v${version}" -m "Release v${version} (${release_type})"
    
    echo "Pushing to origin..."
    git push origin master
    git push origin "v${version}"
    
    echo -e "${GREEN}GitHub release v${version} created successfully!${RESET}"
    echo "You can now create the release on GitHub with the built packages."
    
    return 0
}

# Main execution starts here
# Check if we are in the project root
if [ ! -f "pubspec.yaml" ]; then
    if [ -f "../pubspec.yaml" ]; then
        cd ..
    else
        echo -e "${RED}Error: This script must be run from the project root directory or the scripts directory!${RESET}"
        exit 1
    fi
fi

# Get current version from pubspec.yaml
VERSION=$(grep 'version:' pubspec.yaml | awk '{print $2}' | tr -d "'")
CURRENT_VERSION=$VERSION

# Default values
PACKAGE_TYPE="all"
VERSION_TYPE="patch"
DISTRO=""
LOCAL_ONLY=false
SKIP_BUILD=false
BUILD_ONLY=false
RUN_ONLY=false

# Handle main menu
handle_main_menu() {
    local choice
    while true; do
        show_main_menu
        read -r choice
        
        case "$choice" in
            1) handle_build_menu ;;
            2) handle_release_menu ;;
            3) handle_debug_menu ;;
            4) handle_installation_menu ;;
            5) handle_maintenance_menu ;;
            6) handle_system_setup_menu ;;
            0) 
                echo -e "${BLUE}Exiting. Goodbye!${RESET}"
                exit 0 
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Handle build menu
handle_build_menu() {
    local choice
    while true; do
        show_build_menu
        read -r choice
        
        case "$choice" in
            1)
                echo -e "${BLUE}Building all packages...${RESET}"
                flutter pub get
                build_packages "all" "$VERSION" "release"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            2)
                echo -e "${BLUE}Building DEB package...${RESET}"
                flutter pub get
                build_packages "deb" "$VERSION" "release"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            3)
                echo -e "${BLUE}Building RPM package...${RESET}"
                flutter pub get
                build_packages "rpm" "$VERSION" "release"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            4)
                echo -e "${BLUE}Building AppImage...${RESET}"
                flutter pub get
                build_packages "appimage" "$VERSION" "release"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            5)
                echo -e "${BLUE}Building Arch package...${RESET}"
                flutter pub get
                build_packages "arch" "$VERSION" "release"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            0) return ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Handle release menu
handle_release_menu() {
    local choice
    while true; do
        show_release_menu
        read -r choice
        
        case "$choice" in
            1)
                VERSION_TYPE="patch"
                create_release
                ;;
            2)
                VERSION_TYPE="minor"
                create_release
                ;;
            3)
                VERSION_TYPE="major"
                create_release
                ;;
            4)
                VERSION_TYPE="patch"
                LOCAL_ONLY=true
                create_release
                LOCAL_ONLY=false  # Reset for future use
                ;;
            0) return ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Create release with current settings
create_release() {
    # Get dependencies
    flutter pub get
    
    # Calculate new version
    NEW_VERSION=$(increment_version "$VERSION" "$VERSION_TYPE")
    
    # Confirm version increment
    echo -e "${YELLOW}Increment version from $VERSION to $NEW_VERSION? (y/n) ${RESET}"
    read -n 1 -r REPLY
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        VERSION=$NEW_VERSION
        # Update pubspec.yaml version
        sed -i "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
        echo -e "${GREEN}Version updated to $NEW_VERSION in pubspec.yaml${RESET}"
    else
        echo -e "${RED}Version update cancelled.${RESET}"
        return
    fi
    
    # Build packages
    build_packages "$PACKAGE_TYPE" "$VERSION" "release"
    
    # Create GitHub release if not local-only
    if [ "$LOCAL_ONLY" = false ]; then
        github_release "$VERSION" "$VERSION_TYPE"
    fi
    
    # Update current version for future menu displays
    CURRENT_VERSION=$VERSION
    
    echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
    read -r
}

# Handle debug menu
handle_debug_menu() {
    local choice
    while true; do
        show_debug_menu
        read -r choice
        
        case "$choice" in
            1)
                echo -e "${BLUE}Building and running debug version...${RESET}"
                flutter pub get
                flutter build linux --debug
                flutter run -d linux
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            2)
                echo -e "${BLUE}Running existing debug build...${RESET}"
                flutter run -d linux
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            3)
                echo -e "${BLUE}Building debug version without running...${RESET}"
                flutter pub get
                flutter build linux --debug
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            4)
                echo -e "${BLUE}Running Flutter analyze...${RESET}"
                run_analyze
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            0) return ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Handle installation menu
handle_installation_menu() {
    local choice
    while true; do
        show_installation_menu
        read -r choice
        
        case "$choice" in
            1)
                echo -e "${BLUE}Building and installing locally...${RESET}"
                flutter pub get
                build_packages "all" "$VERSION" "release"
                install_local
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            2)
                echo -e "${BLUE}Installing from existing build...${RESET}"
                install_local
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            0) return ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Handle maintenance menu
handle_maintenance_menu() {
    local choice
    while true; do
        show_maintenance_menu
        read -r choice
        
        case "$choice" in
            1)
                echo -e "${BLUE}Cleaning build directories...${RESET}"
                clean_build
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            2)
                echo -e "${BLUE}Running Flutter analyze...${RESET}"
                run_analyze
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            0) return ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Handle system setup menu
handle_system_setup_menu() {
    local choice
    while true; do
        show_system_setup_menu
        read -r choice
        
        case "$choice" in
            1)
                detect_distro
                install_dependencies "$DISTRO"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            2)
                DISTRO="ubuntu"
                install_dependencies "$DISTRO"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            3)
                DISTRO="fedora"
                install_dependencies "$DISTRO"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            4)
                DISTRO="arch"
                install_dependencies "$DISTRO"
                echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
                read -r
                ;;
            0) return ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Start the interactive menu
handle_main_menu

exit 0
