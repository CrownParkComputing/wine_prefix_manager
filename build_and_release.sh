#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="wine_prefix_manager"
GITHUB_REPO="your-username/wine_prefix_manager"  # Update this with your actual repo
BUILD_DIR="build/linux/x64/release/bundle"
APPIMAGE_DIR="appimage"
APPIMAGE_NAME="WinePrefixManager"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [patch|minor|major]"
    echo ""
    echo "Version types:"
    echo "  patch - Bug fixes, small changes (1.0.0 -> 1.0.1)"
    echo "  minor - New features, backwards compatible (1.0.0 -> 1.1.0)"
    echo "  major - Breaking changes (1.0.0 -> 2.0.0)"
    echo ""
    echo "Example: $0 patch"
    exit 1
}

# Function to get current version from pubspec.yaml
get_current_version() {
    grep "^version:" pubspec.yaml | cut -d' ' -f2 | cut -d'+' -f1
}

# Function to increment version
increment_version() {
    local version=$1
    local type=$2
    
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    local major=${VERSION_PARTS[0]}
    local minor=${VERSION_PARTS[1]}
    local patch=${VERSION_PARTS[2]}
    
    case $type in
        "patch")
            patch=$((patch + 1))
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        *)
            print_error "Invalid version type: $type"
            show_usage
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to update version in pubspec.yaml
update_pubspec_version() {
    local new_version=$1
    local build_number=$(date +%s)  # Use timestamp as build number
    
    print_status "Updating pubspec.yaml to version $new_version+$build_number"
    sed -i "s/^version:.*/version: $new_version+$build_number/" pubspec.yaml
}

# Function to check if git is clean
check_git_status() {
    if [[ -n $(git status --porcelain) ]]; then
        print_warning "You have uncommitted changes. Do you want to continue? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_error "Aborting due to uncommitted changes"
            exit 1
        fi
    fi
}

# Function to check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check Flutter
    if ! command -v flutter &> /dev/null; then
        print_error "Flutter is not installed or not in PATH"
        exit 1
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed or not in PATH"
        exit 1
    fi
    
    # Check GitHub CLI (optional but recommended)
    if ! command -v gh &> /dev/null; then
        print_warning "GitHub CLI (gh) is not installed. Release creation will be skipped."
        print_warning "Install with: sudo apt install gh (or your package manager)"
    fi
    
    # Check required tools for AppImage creation
    if ! command -v wget &> /dev/null; then
        print_error "wget is required for AppImage creation"
        exit 1
    fi
    
    print_success "Dependencies check passed"
}

# Function to clean and build Flutter app
build_flutter_app() {
    print_status "Building Flutter application..."
    
    # Clean previous builds
    flutter clean
    
    # Get dependencies
    flutter pub get
    
    # Build release version
    flutter build linux --release
    
    if [[ ! -d "$BUILD_DIR" ]]; then
        print_error "Build failed: $BUILD_DIR not found"
        exit 1
    fi
    
    print_success "Flutter build completed"
}

# Function to create AppImage
create_appimage() {
    local version=$1
    print_status "Creating AppImage for version $version..."
    
    # Create AppImage directory structure
    mkdir -p "$APPIMAGE_DIR"
    cd "$APPIMAGE_DIR"
    
    # Create AppDir structure
    mkdir -p "AppDir/usr/bin"
    mkdir -p "AppDir/usr/lib"
    mkdir -p "AppDir/usr/share/applications"
    mkdir -p "AppDir/usr/share/icons/hicolor/256x256/apps"
    
    # Copy built application
    cp -r "../$BUILD_DIR"/* "AppDir/usr/bin/"
    
    # Create desktop file
    cat > "AppDir/usr/share/applications/$APP_NAME.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Wine Prefix Manager
Comment=Manage Wine prefixes with ease
Exec=$APP_NAME
Icon=$APP_NAME
Categories=Utility;System;
Terminal=false
StartupWMClass=wine_prefix_manager
EOF
    
    # Create icon (you should replace this with your actual icon)
    # For now, create a simple placeholder
    if [[ ! -f "AppDir/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" ]]; then
        print_warning "No app icon found. Creating placeholder..."
        # You should add your actual icon file here
        # cp ../assets/icon.png "AppDir/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
        
        # Create a simple placeholder icon using ImageMagick if available
        if command -v convert &> /dev/null; then
            convert -size 256x256 xc:lightblue -pointsize 24 -fill black -gravity center -annotate 0 "WPM" "AppDir/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"
        else
            print_warning "ImageMagick not found. AppImage will have no icon."
        fi
    fi
    
    # Make AppRun executable
    cp "AppDir/usr/share/applications/$APP_NAME.desktop" "AppDir/"
    cp "AppDir/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" "AppDir/" 2>/dev/null || true
    
    # Create AppRun script
    cat > "AppDir/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/wine_prefix_manager" "$@"
EOF
    
    chmod +x "AppDir/AppRun"
    
    # Download appimagetool if not present
    if [[ ! -f "appimagetool-x86_64.AppImage" ]]; then
        print_status "Downloading appimagetool..."
        wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x "appimagetool-x86_64.AppImage"
    fi
    
    # Create AppImage
    print_status "Building AppImage..."
    export ARCH=x86_64
    ./appimagetool-x86_64.AppImage "AppDir" "${APPIMAGE_NAME}-${version}-x86_64.AppImage"
    
    if [[ -f "${APPIMAGE_NAME}-${version}-x86_64.AppImage" ]]; then
        print_success "AppImage created: ${APPIMAGE_NAME}-${version}-x86_64.AppImage"
        # Make it executable
        chmod +x "${APPIMAGE_NAME}-${version}-x86_64.AppImage"
        # Move to project root
        mv "${APPIMAGE_NAME}-${version}-x86_64.AppImage" "../"
        cd ..
        return 0
    else
        print_error "AppImage creation failed"
        cd ..
        return 1
    fi
}

# Function to commit and push changes
commit_and_push() {
    local version=$1
    local version_type=$2
    
    print_status "Committing and pushing changes..."
    
    # Add all changes
    git add .
    
    # Commit with version message
    git commit -m "Release v$version ($version_type version bump)

- Updated version to $version
- Built AppImage for release
- Ready for deployment"
    
    # Push to main branch
    git push origin main
    
    print_success "Changes pushed to GitHub"
}

# Function to create GitHub release
create_github_release() {
    local version=$1
    local appimage_file="${APPIMAGE_NAME}-${version}-x86_64.AppImage"
    
    if ! command -v gh &> /dev/null; then
        print_warning "GitHub CLI not available. Skipping release creation."
        print_warning "You can manually create a release at: https://github.com/$GITHUB_REPO/releases/new"
        return 0
    fi
    
    print_status "Creating GitHub release v$version..."
    
    # Create release notes
    local release_notes="## Wine Prefix Manager v$version

### What's New
- Bug fixes and improvements
- Performance optimizations
- Updated dependencies

### Download
- **Linux AppImage**: ${appimage_file}

### Installation
1. Download the AppImage file
2. Make it executable: \`chmod +x ${appimage_file}\`
3. Run: \`./${appimage_file}\`

### System Requirements
- Linux x86_64
- FUSE (for AppImage support)
- Wine (for prefix management)

---
*Built with Flutter ${FLUTTER_VERSION:-latest}*"
    
    # Create the release
    if gh release create "v$version" \
        --title "Wine Prefix Manager v$version" \
        --notes "$release_notes" \
        --draft=false \
        --prerelease=false; then
        
        print_success "GitHub release v$version created"
        
        # Upload AppImage as asset
        if [[ -f "$appimage_file" ]]; then
            print_status "Uploading AppImage to release..."
            if gh release upload "v$version" "$appimage_file"; then
                print_success "AppImage uploaded to release"
            else
                print_error "Failed to upload AppImage"
            fi
        fi
    else
        print_error "Failed to create GitHub release"
        return 1
    fi
}

# Function to launch AppImage
launch_appimage() {
    local version=$1
    local appimage_file="${APPIMAGE_NAME}-${version}-x86_64.AppImage"
    
    if [[ -f "$appimage_file" ]]; then
        print_status "Launching $appimage_file..."
        ./"$appimage_file" &
        print_success "AppImage launched successfully!"
    else
        print_error "AppImage file not found: $appimage_file"
    fi
}

# Main script execution
main() {
    # Check if version type is provided
    if [[ $# -eq 0 ]]; then
        show_usage
    fi
    
    local version_type=$1
    
    # Validate version type
    if [[ ! "$version_type" =~ ^(patch|minor|major)$ ]]; then
        print_error "Invalid version type: $version_type"
        show_usage
    fi
    
    print_status "Starting build and release process for $version_type version bump..."
    
    # Check dependencies
    check_dependencies
    
    # Check git status
    check_git_status
    
    # Get current version and calculate new version
    local current_version
    current_version=$(get_current_version)
    local new_version
    new_version=$(increment_version "$current_version" "$version_type")
    
    print_status "Current version: $current_version"
    print_status "New version: $new_version"
    
    # Confirm with user
    echo ""
    print_warning "This will:"
    echo "  1. Update version from $current_version to $new_version"
    echo "  2. Build Flutter app for Linux"
    echo "  3. Create AppImage"
    echo "  4. Commit and push to GitHub"
    echo "  5. Create GitHub release"
    echo "  6. Launch the AppImage"
    echo ""
    echo "Do you want to continue? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
    fi
    
    # Update version in pubspec.yaml
    update_pubspec_version "$new_version"
    
    # Build Flutter application
    build_flutter_app
    
    # Create AppImage
    if ! create_appimage "$new_version"; then
        print_error "AppImage creation failed. Aborting."
        exit 1
    fi
    
    # Commit and push changes
    commit_and_push "$new_version" "$version_type"
    
    # Create GitHub release
    create_github_release "$new_version"
    
    # Launch AppImage
    print_status "Build and release process completed successfully!"
    echo ""
    print_warning "Would you like to launch the AppImage now? (y/N)"
    read -r launch_response
    if [[ "$launch_response" =~ ^[Yy]$ ]]; then
        launch_appimage "$new_version"
    fi
    
    print_success "All done! 🎉"
    echo ""
    echo "Summary:"
    echo "  ✓ Version bumped to $new_version"
    echo "  ✓ AppImage created: ${APPIMAGE_NAME}-${new_version}-x86_64.AppImage"
    echo "  ✓ Changes pushed to GitHub"
    echo "  ✓ GitHub release created"
    echo ""
    echo "You can download the release at:"
    echo "  https://github.com/$GITHUB_REPO/releases/tag/v$new_version"
}

# Run main function with all arguments
main "$@" 