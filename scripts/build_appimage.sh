#!/bin/bash

# Simple AppImage builder for Wine Prefix Manager

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Get project info
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION=$(grep "^version:" "$PROJECT_ROOT/pubspec.yaml" | sed 's/version: *//g' | sed 's/+.*//' | tr -d '"' | tr -d "'")

echo -e "${BLUE}Building AppImage for Wine Prefix Manager v$VERSION${NC}"

# Build Flutter app
echo -e "${BLUE}Building Flutter app...${NC}"
cd "$PROJECT_ROOT"
flutter clean
flutter pub get
flutter build linux --release

BUILD_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
APPIMAGE_DIR="$PROJECT_ROOT/appimage"
APPDIR="$APPIMAGE_DIR/WinePrefixManager.AppDir"

if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${RED}Flutter build failed${NC}"
    exit 1
fi

# Create AppDir
echo -e "${BLUE}Creating AppDir...${NC}"
rm -rf "$APPDIR"
mkdir -p "$APPDIR"

# Copy Flutter app
cp -r "$BUILD_DIR"/* "$APPDIR/"
chmod +x "$APPDIR/wine_prefix_manager"

# Create desktop file
cat > "$APPDIR/wine_prefix_manager.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Wine Prefix Manager
Comment=Manage Wine prefixes with ease
Exec=wine_prefix_manager
Icon=wine_prefix_manager
Categories=System;Utility;
Terminal=false
EOF

# Create simple icon (if not exists)
if [ ! -f "$APPDIR/wine_prefix_manager.png" ]; then
    # Create a simple colored square as fallback icon
    echo -e "${BLUE}Creating fallback icon...${NC}"
    cat > "$APPDIR/wine_prefix_manager.svg" << 'EOF'
<svg width="256" height="256" xmlns="http://www.w3.org/2000/svg">
  <rect width="256" height="256" fill="#722F37"/>
  <circle cx="128" cy="128" r="80" fill="#FFF"/>
  <text x="128" y="140" font-family="Arial" font-size="60" text-anchor="middle" fill="#722F37">W</text>
</svg>
EOF
    
    if command -v convert &> /dev/null; then
        convert "$APPDIR/wine_prefix_manager.svg" "$APPDIR/wine_prefix_manager.png"
        rm "$APPDIR/wine_prefix_manager.svg"
    else
        mv "$APPDIR/wine_prefix_manager.svg" "$APPDIR/wine_prefix_manager.png"
    fi
fi

# Create AppRun
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
APPDIR="$(dirname "$(readlink -f "$0")")"
export PATH="$APPDIR:$PATH"
exec "$APPDIR/wine_prefix_manager" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Download appimagetool if needed
cd "$APPIMAGE_DIR"
if [ ! -f "appimagetool-x86_64.AppImage" ]; then
    echo -e "${BLUE}Downloading appimagetool...${NC}"
    wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x appimagetool-x86_64.AppImage
fi

# Build AppImage
echo -e "${BLUE}Building AppImage...${NC}"
OUTPUT_NAME="WinePrefixManager-$VERSION-x86_64.AppImage"
./appimagetool-x86_64.AppImage "$APPDIR" "$OUTPUT_NAME" --no-appstream

if [ -f "$OUTPUT_NAME" ]; then
    echo -e "${GREEN}✅ AppImage created: $OUTPUT_NAME${NC}"
    echo -e "${GREEN}Location: $APPIMAGE_DIR/$OUTPUT_NAME${NC}"
else
    echo -e "${RED}❌ AppImage creation failed${NC}"
    exit 1
fi 