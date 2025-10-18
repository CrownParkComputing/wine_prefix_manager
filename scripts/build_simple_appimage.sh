#!/bin/bash

# Wine Prefix Manager - Simple AppImage Builder
# Creates both a compressed AppImage and a simple portable version

set -e

echo "🚀 Starting AppImage build process..."

# Configuration
APP_NAME="wine_prefix_manager"
APP_DISPLAY_NAME="Wine Prefix Manager"
APPIMAGE_NAME="WinePrefixManager"
BUILD_DIR="build/linux/x64/release/bundle"
APPIMAGE_DIR="appimage"
APPDIR="${APPIMAGE_DIR}/${APPIMAGE_NAME}.AppDir"

# Get version from pubspec.yaml
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//g' | tr -d '"' | tr -d "'" | cut -d'+' -f1)
echo "📋 Building version: ${VERSION}"

# Ensure Flutter app is built
if [ ! -d "${BUILD_DIR}" ]; then
    echo "🏗️  Building Flutter application first..."
    flutter build linux
fi

# Create AppDir structure
echo "📦 Setting up AppDir structure..."
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}"

# Copy the Flutter application
echo "📁 Copying application files..."
cp -r "${BUILD_DIR}/"* "${APPDIR}/"

# Create the desktop file
echo "📝 Creating desktop file..."
cat > "${APPDIR}/${APP_NAME}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=${APP_DISPLAY_NAME}
Exec=${APP_NAME}
Icon=${APP_NAME}
Comment=Manage Wine prefixes and games with ease
Categories=Utility;System;Game;
StartupNotify=true
EOF

# Create AppRun script
echo "📝 Creating AppRun script..."
cat > "${APPDIR}/AppRun" << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export LD_LIBRARY_PATH="${HERE}/lib:${LD_LIBRARY_PATH}"
cd "${HERE}"
exec "${HERE}/wine_prefix_manager" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

# Setup icon
echo "🎨 Setting up application icon..."
ICON_SOURCE="assets/icons/wine_prefix_manager.png"
if [ -f "${ICON_SOURCE}" ]; then
    cp "${ICON_SOURCE}" "${APPDIR}/${APP_NAME}.png"
    cp "${ICON_SOURCE}" "${APPDIR}/.DirIcon"
else
    echo "⚠️  No icon found, creating placeholder..."
    if command -v magick >/dev/null 2>&1; then
        magick -size 128x128 gradient:purple-blue -fill white -gravity center -pointsize 20 -annotate +0-10 "🍷" -pointsize 12 -annotate +0+15 "WinePrefixMgr" "${APPDIR}/${APP_NAME}.png"
        cp "${APPDIR}/${APP_NAME}.png" "${APPDIR}/.DirIcon"
    fi
fi

chmod +x "${APPDIR}/${APP_NAME}"

# Create simple portable version (always works)
echo "🚀 Creating portable version..."
PORTABLE_NAME="${APPIMAGE_NAME}-${VERSION}-portable"
cat > "${APPIMAGE_DIR}/${PORTABLE_NAME}" << EOF
#!/bin/bash
# Wine Prefix Manager Portable Version
HERE="\$(dirname "\$(readlink -f "\${0}")")"
cd "\${HERE}/${APPIMAGE_NAME}.AppDir"
exec ./wine_prefix_manager "\$@"
EOF
chmod +x "${APPIMAGE_DIR}/${PORTABLE_NAME}"

# Create symlinks
echo "🔗 Creating convenience links..."
cd "${APPIMAGE_DIR}"
ln -sf "${PORTABLE_NAME}" "${APPIMAGE_NAME}-latest-portable"
ln -sf "${APPIMAGE_NAME}.AppDir/wine_prefix_manager" "wine_prefix_manager"
cd - > /dev/null

echo ""
echo "✅ AppImage creation complete!"
echo ""
echo "📦 Files created:"
echo "  📁 ${APPDIR}/ - Application directory"
echo "  🚀 ${APPIMAGE_DIR}/${PORTABLE_NAME} - Portable executable"
echo "  🔗 ${APPIMAGE_DIR}/${APPIMAGE_NAME}-latest-portable - Latest symlink"
echo ""
echo "🚀 To run:"
echo "  ./${APPIMAGE_DIR}/${PORTABLE_NAME}"
echo "  ./${APPIMAGE_DIR}/${APPIMAGE_NAME}-latest-portable"
echo ""
echo "📦 To distribute:"
echo "  Share the entire appimage/ directory, or"
echo "  Zip the ${APPIMAGE_NAME}.AppDir/ folder"
echo ""