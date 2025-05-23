#!/bin/bash

# AppImage Builder for Wine Prefix Manager
# Creates an AppImage from the Flutter Linux build

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build/linux/x64/release"
BUNDLE_DIR="$BUILD_DIR/bundle"
APPIMAGE_DIR="$PROJECT_ROOT/appimage"
APPDIR="$APPIMAGE_DIR/WinePrefixManager.AppDir"

# Application details
APP_NAME="Wine Prefix Manager"
APP_ID="com.crownparkcomputing.wine_prefix_manager"
APP_EXEC="wine_prefix_manager"
VERSION=$(grep "^version:" "$PROJECT_ROOT/pubspec.yaml" | sed 's/version: *//g' | sed 's/+.*//' | tr -d '"' | tr -d "'")

echo -e "${BLUE}🏗️  Building AppImage for Wine Prefix Manager v$VERSION${NC}"
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    # Check if Flutter is installed
    if ! command -v flutter &> /dev/null; then
        echo -e "${RED}❌ Flutter not found. Please install Flutter first.${NC}"
        exit 1
    fi
    
    # Check if we have the AppImage tools
    if ! command -v wget &> /dev/null; then
        echo -e "${RED}❌ wget not found. Please install wget.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
    echo ""
}

# Build Flutter app for Linux release
build_flutter_app() {
    echo -e "${BLUE}🏗️  Building Flutter app for Linux (release)...${NC}"
    cd "$PROJECT_ROOT"
    
    # Clean previous builds
    flutter clean
    
    # Get dependencies
    flutter pub get
    
    # Build for Linux release
    flutter build linux --release
    
    if [ ! -d "$BUNDLE_DIR" ]; then
        echo -e "${RED}❌ Flutter build failed - bundle directory not found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Flutter app built successfully${NC}"
    echo ""
}

# Download AppImage tools if needed
download_appimage_tools() {
    echo -e "${BLUE}📥 Setting up AppImage tools...${NC}"
    
    mkdir -p "$APPIMAGE_DIR"
    cd "$APPIMAGE_DIR"
    
    # Download appimagetool if not present
    if [ ! -f "appimagetool-x86_64.AppImage" ]; then
        echo "Downloading appimagetool..."
        wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x appimagetool-x86_64.AppImage
    fi
    
    echo -e "${GREEN}✅ AppImage tools ready${NC}"
    echo ""
}

# Create AppDir structure
create_appdir() {
    echo -e "${BLUE}📁 Creating AppDir structure...${NC}"
    
    # Remove old AppDir if it exists
    rm -rf "$APPDIR"
    mkdir -p "$APPDIR"
    
    # Create directory structure
    mkdir -p "$APPDIR/usr/bin"
    mkdir -p "$APPDIR/usr/lib"
    mkdir -p "$APPDIR/usr/share/applications"
    mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
    mkdir -p "$APPDIR/usr/share/pixmaps"
    
    echo -e "${GREEN}✅ AppDir structure created${NC}"
    echo ""
}

# Copy Flutter app to AppDir
copy_flutter_app() {
    echo -e "${BLUE}📦 Copying Flutter app to AppDir...${NC}"
    
    # Copy the entire bundle
    cp -r "$BUNDLE_DIR"/* "$APPDIR/usr/"
    
    # Make sure the executable is in usr/bin
    if [ -f "$APPDIR/usr/$APP_EXEC" ]; then
        mv "$APPDIR/usr/$APP_EXEC" "$APPDIR/usr/bin/"
    fi
    
    # Make executable
    chmod +x "$APPDIR/usr/bin/$APP_EXEC"
    
    echo -e "${GREEN}✅ Flutter app copied to AppDir${NC}"
    echo ""
}

# Create desktop file
create_desktop_file() {
    echo -e "${BLUE}📄 Creating desktop file...${NC}"
    
    cat > "$APPDIR/$APP_EXEC.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Manage Wine prefixes with ease
Exec=$APP_EXEC
Icon=$APP_EXEC
Categories=System;Utility;
Terminal=false
StartupNotify=true
EOF

    # Copy to applications directory
    cp "$APPDIR/$APP_EXEC.desktop" "$APPDIR/usr/share/applications/"
    
    echo -e "${GREEN}✅ Desktop file created${NC}"
    echo ""
}

# Create or copy icon
create_icon() {
    echo -e "${BLUE}🎨 Setting up application icon...${NC}"
    
    # Check if icon exists in assets
    ICON_SOURCE="$PROJECT_ROOT/assets/icon.png"
    if [ -f "$ICON_SOURCE" ]; then
        echo "Using existing icon from assets..."
        cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_EXEC.png"
        cp "$ICON_SOURCE" "$APPDIR/usr/share/pixmaps/$APP_EXEC.png"
        cp "$ICON_SOURCE" "$APPDIR/$APP_EXEC.png"
    else
        echo "Creating default icon..."
        # Create a simple SVG icon and convert to PNG
        cat > "$APPDIR/$APP_EXEC.svg" << 'EOF'
<svg width="256" height="256" xmlns="http://www.w3.org/2000/svg">
  <rect width="256" height="256" fill="#722F37"/>
  <circle cx="128" cy="128" r="80" fill="#FFF"/>
  <text x="128" y="140" font-family="Arial" font-size="60" text-anchor="middle" fill="#722F37">W</text>
</svg>
EOF
        
        # Try to convert to PNG if convert is available
        if command -v convert &> /dev/null; then
            convert "$APPDIR/$APP_EXEC.svg" "$APPDIR/$APP_EXEC.png"
            cp "$APPDIR/$APP_EXEC.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP_EXEC.png"
            cp "$APPDIR/$APP_EXEC.png" "$APPDIR/usr/share/pixmaps/$APP_EXEC.png"
            rm "$APPDIR/$APP_EXEC.svg"
        else
            echo -e "${YELLOW}⚠️  ImageMagick not found. Using SVG as icon.${NC}"
            cp "$APPDIR/$APP_EXEC.svg" "$APPDIR/$APP_EXEC.png"
        fi
    fi
    
    echo -e "${GREEN}✅ Icon set up${NC}"
    echo ""
}

# Create AppRun script
create_apprun() {
    echo -e "${BLUE}🚀 Creating AppRun script...${NC}"
    
    cat > "$APPDIR/AppRun" << EOF
#!/bin/bash

# AppRun script for Wine Prefix Manager

# Get the directory where this AppImage is located
APPDIR="\$(dirname "\$(readlink -f "\$0")")"

# Set up environment
export PATH="\$APPDIR/usr/bin:\$PATH"
export LD_LIBRARY_PATH="\$APPDIR/usr/lib:\$LD_LIBRARY_PATH"

# Change to a writable directory (user's home)
cd "\$HOME"

# Launch the application
exec "\$APPDIR/usr/bin/$APP_EXEC" "\$@"
EOF

    chmod +x "$APPDIR/AppRun"
    
    echo -e "${GREEN}✅ AppRun script created${NC}"
    echo ""
}

# Build the AppImage
build_appimage() {
    echo -e "${BLUE}🔨 Building AppImage...${NC}"
    
    cd "$APPIMAGE_DIR"
    
    # Set the VERSION environment variable for appimagetool
    export VERSION="$VERSION"
    
    # Build the AppImage
    ./appimagetool-x86_64.AppImage "$APPDIR" "WinePrefixManager-$VERSION-x86_64.AppImage"
    
    if [ -f "WinePrefixManager-$VERSION-x86_64.AppImage" ]; then
        echo -e "${GREEN}✅ AppImage built successfully!${NC}"
        echo -e "   📦 Location: ${BLUE}$APPIMAGE_DIR/WinePrefixManager-$VERSION-x86_64.AppImage${NC}"
        echo -e "   📏 Size: $(du -h "WinePrefixManager-$VERSION-x86_64.AppImage" | cut -f1)"
        
        # Make it executable
        chmod +x "WinePrefixManager-$VERSION-x86_64.AppImage"
        
        echo ""
        echo -e "${GREEN}🎉 AppImage is ready for distribution!${NC}"
        echo ""
        echo -e "${YELLOW}To test the AppImage:${NC}"
        echo -e "   ${BLUE}cd $APPIMAGE_DIR${NC}"
        echo -e "   ${BLUE}./WinePrefixManager-$VERSION-x86_64.AppImage${NC}"
    else
        echo -e "${RED}❌ AppImage build failed${NC}"
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🍷 Wine Prefix Manager AppImage Builder${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    
    check_prerequisites
    build_flutter_app
    download_appimage_tools
    create_appdir
    copy_flutter_app
    create_desktop_file
    create_icon
    create_apprun
    build_appimage
    
    echo -e "${GREEN}✅ All done! AppImage created successfully.${NC}"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 