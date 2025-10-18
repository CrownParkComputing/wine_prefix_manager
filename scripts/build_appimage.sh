#!/bin/bash

# Wine Prefix Manager AppImage Build Script
# This script creates an AppImage from the built Flutter application

set -e  # Exit on any error

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

# Check if Flutter app is built
if [ ! -d "${BUILD_DIR}" ]; then
    echo "❌ Flutter application not found in ${BUILD_DIR}"
    echo "   Please run 'flutter build linux' first"
    exit 1
fi

# Check if appimagetool exists
APPIMAGETOOL="${APPIMAGE_DIR}/appimagetool-x86_64.AppImage"
if [ ! -f "${APPIMAGETOOL}" ]; then
    echo "📥 Downloading appimagetool..."
    mkdir -p "${APPIMAGE_DIR}"
    wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O "${APPIMAGETOOL}"
    chmod +x "${APPIMAGETOOL}"
fi

# Clean and create AppDir structure
echo "🏗️  Setting up AppDir structure..."
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}"

# Copy the Flutter application
echo "📦 Copying application files..."
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

# AppRun script for Wine Prefix Manager
SELF=$(readlink -f "$0")
HERE=${SELF%/*}

# Set up environment
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/lib:${HERE}/usr/lib:${LD_LIBRARY_PATH}"

# Change to the AppDir for relative paths to work
cd "${HERE}"

# Run the application
exec "${HERE}/wine_prefix_manager" "$@"
EOF

chmod +x "${APPDIR}/AppRun"

# Copy or create icon
echo "🎨 Setting up application icon..."
ICON_SOURCE="assets/icons/wine_prefix_manager.png"
if [ -f "${ICON_SOURCE}" ]; then
    cp "${ICON_SOURCE}" "${APPDIR}/${APP_NAME}.png"
    cp "${ICON_SOURCE}" "${APPDIR}/.DirIcon"
else
    # Create a simple placeholder icon if none exists
    echo "⚠️  No icon found at ${ICON_SOURCE}, creating placeholder..."
    # Create a 128x128 PNG placeholder (requires ImageMagick)
    if command -v convert >/dev/null 2>&1; then
        convert -size 128x128 xc:blue -fill white -gravity center -pointsize 20 -annotate +0+0 "WPM" "${APPDIR}/${APP_NAME}.png"
        cp "${APPDIR}/${APP_NAME}.png" "${APPDIR}/.DirIcon"
    else
        echo "⚠️  ImageMagick not found, skipping icon creation"
        touch "${APPDIR}/${APP_NAME}.png"
        touch "${APPDIR}/.DirIcon"
    fi
fi

# Make the main executable runnable
chmod +x "${APPDIR}/${APP_NAME}"

# Build the AppImage
echo "🔨 Building AppImage..."
OUTPUT_NAME="${APPIMAGE_NAME}-${VERSION}-x86_64.AppImage"
OUTPUT_PATH="${APPIMAGE_DIR}/${OUTPUT_NAME}"

# Remove existing AppImage if it exists
[ -f "${OUTPUT_PATH}" ] && rm -f "${OUTPUT_PATH}"

# First, let's try the simple approach - just use tar to create a portable archive
echo "� Creating portable AppImage archive..."
cd "${APPIMAGE_DIR}"

# Create a self-extracting archive
cat > "${OUTPUT_NAME}" << 'EOF'
#!/bin/bash
# Wine Prefix Manager Portable AppImage
# Extract with --appimage-extract or run directly

SELF=$(readlink -f "$0")
HERE=$(dirname "$SELF")

if [ "$1" = "--appimage-extract" ] || [ "$1" = "--extract" ]; then
    echo "Extracting Wine Prefix Manager..."
    TMPDIR=$(mktemp -d)
    tail -n +25 "$0" | tar -xzf - -C "$TMPDIR" 2>/dev/null || {
        echo "❌ Extraction failed"
        rmdir "$TMPDIR" 2>/dev/null
        exit 1
    }
    if [ -d "$TMPDIR/WinePrefixManager.AppDir" ]; then
        mv "$TMPDIR/WinePrefixManager.AppDir" "./squashfs-root"
        rmdir "$TMPDIR"
        echo "Extracted to: ./squashfs-root"
        echo "Run with: ./squashfs-root/AppRun"
    else
        echo "❌ Extraction failed - AppDir not found"
        rm -rf "$TMPDIR"
        exit 1
    fi
elif [ "$1" = "--help" ] || [ "$1" = "--appimage-help" ]; then
    echo "Wine Prefix Manager AppImage"
    echo "Usage: $0 [options]"
    echo "  --appimage-extract  Extract contents"
    echo "  --help             Show this help"
    echo "  (no args)          Run application"
else
    # Run the application directly
    TMPDIR=$(mktemp -d)
    tail -n +25 "$0" | tar -xzf - -C "$TMPDIR" 2>/dev/null || {
        echo "❌ Failed to extract AppImage"
        rmdir "$TMPDIR" 2>/dev/null
        exit 1
    }
    if [ -d "$TMPDIR/WinePrefixManager.AppDir" ]; then
        cd "$TMPDIR/WinePrefixManager.AppDir"
        exec ./AppRun "$@"
    else
        echo "❌ AppImage corrupted - cannot find application"
        rm -rf "$TMPDIR"
        exit 1
    fi
fi
exit $?
# AppImage data follows - do not edit below this line
EOF

# Create the tar archive and append it
tar -czf "${OUTPUT_NAME}.tar.gz" "${APPIMAGE_NAME}.AppDir"
cat "${OUTPUT_NAME}.tar.gz" >> "${OUTPUT_NAME}"
rm -f "${OUTPUT_NAME}.tar.gz"
cd - > /dev/null

# Create symlink for latest version
echo "🔗 Creating latest version symlink..."
cd "${APPIMAGE_DIR}"
ln -sf "${OUTPUT_NAME}" "${APPIMAGE_NAME}-latest.AppImage"
cd - > /dev/null

# Set permissions
chmod +x "${OUTPUT_PATH}"

echo ""
echo "✅ AppImage build complete!"
echo "📁 Location: ${OUTPUT_PATH}"
echo "📊 Size: $(du -h "${OUTPUT_PATH}" | cut -f1)"
echo ""
echo "🚀 To run: ./${OUTPUT_PATH}"
echo "📋 To test: ${OUTPUT_PATH} --appimage-help"