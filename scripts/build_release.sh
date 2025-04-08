#!/bin/bash

# Wine Prefix Manager Release Builder
# This script builds a release version for Linux and creates distributable artifacts

set -e  # Exit on error

VERSION="1.7.0"
APP_NAME="wine_prefix_manager"
RELEASE_DIR="release"
BUILD_DIR="build/linux/x64/release/bundle"

echo "Building Wine Prefix Manager v${VERSION} for Linux..."

# Ensure the script is run from the project root
if [ ! -f "pubspec.yaml" ]; then
    echo "Error: This script must be run from the project root directory!"
    exit 1
fi

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Build for Linux in release mode
echo "Building Linux release..."
flutter build linux --release

# Create release directory
mkdir -p $RELEASE_DIR

# Package the application
echo "Creating application package..."
PACKAGE_NAME="${APP_NAME}-${VERSION}-linux-x64"
PACKAGE_DIR="${RELEASE_DIR}/${PACKAGE_NAME}"

# Create directory structure
mkdir -p $PACKAGE_DIR

# Copy build artifacts
echo "Copying build artifacts..."
cp -r $BUILD_DIR/* $PACKAGE_DIR/

# Create tarball
echo "Creating tarball..."
cd $RELEASE_DIR
tar -czf "${PACKAGE_NAME}.tar.gz" $PACKAGE_NAME
cd ..

# Create AppImage
echo "Creating AppImage..."
# Create AppDir structure
APPDIR="$RELEASE_DIR/AppDir"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/metainfo"

# Copy the built application - FIX: Copy to the correct location and structure
echo "Copying application files to AppDir..."
# First check if bundle directory contains a single directory with the app
BUNDLE_CONTENTS=$(ls "$BUILD_DIR")
if [ "$(echo "$BUNDLE_CONTENTS" | wc -l)" -eq 1 ] && [ -d "$BUILD_DIR/$BUNDLE_CONTENTS" ]; then
    # If the bundle has a single directory (e.g., 'wine_prefix_manager'), copy its contents
    cp -r "$BUILD_DIR/$BUNDLE_CONTENTS"/* "$APPDIR/usr/bin/"
else
    # Otherwise copy everything directly
    cp -r "$BUILD_DIR/"* "$APPDIR/usr/bin/"
fi

# Check if the executable exists at the expected path
if [ ! -f "$APPDIR/usr/bin/wine_prefix_manager" ]; then
    echo "Warning: Executable not found at expected path. Searching for it..."
    # Look for the executable
    EXECUTABLE=$(find "$BUILD_DIR" -type f -executable -name "wine_prefix_manager" | head -1)
    if [ -n "$EXECUTABLE" ]; then
        echo "Found executable at: $EXECUTABLE"
        # Copy to the correct location
        cp "$EXECUTABLE" "$APPDIR/usr/bin/wine_prefix_manager"
    else
        echo "Error: Could not find wine_prefix_manager executable in build directory"
        # List the contents of the build directory for debugging
        echo "Build directory contents:"
        find "$BUILD_DIR" -type f -executable | sort
        exit 1
    fi
fi

# Verify executable permissions
chmod +x "$APPDIR/usr/bin/wine_prefix_manager"

# Create desktop file - Fix the location and ensure it's properly formatted
echo "Creating desktop file at $APPDIR/usr/share/applications/wine-prefix-manager.desktop"
cat > "$APPDIR/usr/share/applications/wine-prefix-manager.desktop" << EOL
[Desktop Entry]
Type=Application
Name=Wine Prefix Manager
Comment=Manage Wine and Proton prefixes with ease
Exec=wine_prefix_manager
Icon=wine-prefix-manager
Terminal=false
Categories=Utility;Game;
StartupWMClass=wine_prefix_manager
X-AppImage-Name=Wine Prefix Manager
X-AppImage-Version=$VERSION
X-AppImage-Arch=x86_64
EOL

# Verify desktop file was created and contains expected content
echo "Verifying desktop file..."
if [ -f "$APPDIR/usr/share/applications/wine-prefix-manager.desktop" ]; then
    echo "Desktop file exists."
    cat "$APPDIR/usr/share/applications/wine-prefix-manager.desktop"
else
    echo "ERROR: Desktop file was not created!"
    exit 1
fi

# Create a desktop file directly at the root of AppDir (some AppImage tools look here)
echo "Creating desktop file at AppDir root as backup..."
cp "$APPDIR/usr/share/applications/wine-prefix-manager.desktop" "$APPDIR/wine-prefix-manager.desktop"

# Create a .DirIcon symlink (required by some AppImage tools)
echo "Creating .DirIcon symlink..."
ln -sf usr/share/icons/hicolor/256x256/apps/wine-prefix-manager.png "$APPDIR/.DirIcon" || true

# Try to find icon in assets or create a placeholder
ICON_SOURCE="assets/icons/app_icon.png"
if [ ! -f "$ICON_SOURCE" ]; then
    ICON_SOURCE="assets/icon/icon.png"
fi
if [ ! -f "$ICON_SOURCE" ]; then
    ICON_SOURCE="assets/images/icon.png"
fi

if [ -f "$ICON_SOURCE" ]; then
    # Create the icon in the standard location
    cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/256x256/apps/wine-prefix-manager.png"
    
    # IMPORTANT: Also copy the icon to the AppDir root as required by appimagetool
    cp "$ICON_SOURCE" "$APPDIR/wine-prefix-manager.png"
else
    echo "Warning: App icon not found. Using a placeholder."
    # Create a placeholder icon (adjust for ImageMagick v7+)
    if command -v magick &> /dev/null; then
        magick -size 256x256 xc:transparent -font DejaVu-Sans -pointsize 20 -fill black \
            -gravity center -annotate 0 "Wine Prefix Manager" "$APPDIR/usr/share/icons/hicolor/256x256/apps/wine-prefix-manager.png"
        # Also create the icon in the AppDir root
        magick -size 256x256 xc:transparent -font DejaVu-Sans -pointsize 20 -fill black \
            -gravity center -annotate 0 "Wine Prefix Manager" "$APPDIR/wine-prefix-manager.png"
    elif command -v convert &> /dev/null; then
        convert -size 256x256 xc:transparent -font DejaVu-Sans -pointsize 20 -fill black \
            -gravity center -annotate 0 "Wine Prefix Manager" "$APPDIR/usr/share/icons/hicolor/256x256/apps/wine-prefix-manager.png"
        # Also create the icon in the AppDir root
        convert -size 256x256 xc:transparent -font DejaVu-Sans -pointsize 20 -fill black \
            -gravity center -annotate 0 "Wine Prefix Manager" "$APPDIR/wine-prefix-manager.png"
    else
        echo "ImageMagick not found. Creating a simple text file as icon placeholder."
        echo "Wine Prefix Manager" > "$APPDIR/usr/share/icons/hicolor/256x256/apps/wine-prefix-manager.png"
        # Also create the placeholder in the AppDir root
        echo "Wine Prefix Manager" > "$APPDIR/wine-prefix-manager.png"
    fi
fi

# Verify the icon exists at the root of AppDir
if [ -f "$APPDIR/wine-prefix-manager.png" ]; then
    echo "Icon file exists at AppDir root: $APPDIR/wine-prefix-manager.png"
else
    echo "Warning: Icon file not found at AppDir root. Creating a copy now."
    # Try to copy from usr/share if it exists there
    if [ -f "$APPDIR/usr/share/icons/hicolor/256x256/apps/wine-prefix-manager.png" ]; then
        cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/wine-prefix-manager.png" "$APPDIR/wine-prefix-manager.png"
    else
        # Create a minimal placeholder if all else fails
        echo "Wine Prefix Manager" > "$APPDIR/wine-prefix-manager.png"
    fi
fi

# Create AppStream metadata with proper RDNS ID and other required elements
cat > "$APPDIR/usr/share/metainfo/wine-prefix-manager.appdata.xml" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.wine_prefix_manager</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <name>Wine Prefix Manager</name>
  <summary>Manage Wine and Proton prefixes with ease</summary>
  <description>
    <p>
      Wine Prefix Manager helps you create, manage, and backup Wine and Proton prefixes.
      It provides an easy way to manage executables, run applications, and configure prefixes.
    </p>
  </description>
  <url type="homepage">https://github.com/</url>
  <launchable type="desktop-id">wine-prefix-manager.desktop</launchable>
  <provides>
    <binary>wine_prefix_manager</binary>
  </provides>
  <developer_name>Wine Prefix Manager Team</developer_name>
  <releases>
    <release version="$VERSION" date="$(date +%Y-%m-%d)">
      <description>
        <p>Release version $VERSION</p>
      </description>
    </release>
  </releases>
  <content_rating type="oars-1.1" />
</component>
EOL

# Verify AppStream metadata was created
echo "Verifying AppStream metadata..."
if [ -f "$APPDIR/usr/share/metainfo/wine-prefix-manager.appdata.xml" ]; then
    echo "AppStream metadata exists."
else
    echo "ERROR: AppStream metadata was not created!"
    exit 1
fi

# Add GTK dependencies to fix the image-missing and pixbuf loader issues
echo "Adding GTK dependencies to AppDir..."

# Create necessary directories
mkdir -p "$APPDIR/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders"
mkdir -p "$APPDIR/usr/share/icons/Adwaita/scalable/status"

# Find and copy system paths
GTK_PATHS=(
    "/usr/lib/x86_64-linux-gnu"  # Debian/Ubuntu
    "/usr/lib64"                 # Fedora/RHEL
    "/usr/lib"                   # Arch
)

# Copy pixbuf loaders
echo "Copying pixbuf loaders..."
for PATH_BASE in "${GTK_PATHS[@]}"; do
    if [ -d "$PATH_BASE/gdk-pixbuf-2.0" ]; then
        cp -r "$PATH_BASE/gdk-pixbuf-2.0/2.10.0/loaders"/* "$APPDIR/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders/" 2>/dev/null || true
        if [ -f "$PATH_BASE/gdk-pixbuf-2.0/2.10.0/loaders.cache" ]; then
            cp "$PATH_BASE/gdk-pixbuf-2.10.0/loaders.cache" "$APPDIR/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/" || true
        fi
    fi
done

# Find the gdk-pixbuf-query-loaders command
GDK_QUERY_CMD=""
for PATH_BASE in "${GTK_PATHS[@]}"; do
    if [ -x "$PATH_BASE/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders" ]; then
        GDK_QUERY_CMD="$PATH_BASE/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders"
        break
    fi
done

# Generate loaders.cache if we have the command
if [ -n "$GDK_QUERY_CMD" ]; then
    echo "Generating pixbuf loaders.cache..."
    
    # Run in modified environment to include AppDir paths
    env \
        GDK_PIXBUF_MODULEDIR="$APPDIR/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders" \
        "$GDK_QUERY_CMD" > "$APPDIR/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    
    # Fix paths in loaders.cache to use relative paths
    sed -i -e "s|$APPDIR/usr/|/usr/|g" "$APPDIR/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache"
else
    echo "Warning: gdk-pixbuf-query-loaders not found, using system loaders.cache"
fi

# Copy required Adwaita icons
echo "Copying required Adwaita icons..."
ICON_PATHS=(
    "/usr/share/icons/Adwaita"
    "/usr/share/icons/hicolor"
)

for ICON_PATH in "${ICON_PATHS[@]}"; do
    if [ -d "$ICON_PATH" ]; then
        # Copy common status icons needed by GTK
        mkdir -p "$APPDIR$ICON_PATH/scalable/status"
        cp -r "$ICON_PATH/scalable/status"/* "$APPDIR$ICON_PATH/scalable/status/" 2>/dev/null || true
        
        # Copy index.theme files
        if [ -f "$ICON_PATH/index.theme" ]; then
            mkdir -p "$APPDIR$ICON_PATH"
            cp "$ICON_PATH/index.theme" "$APPDIR$ICON_PATH/" || true
        fi
        
        # Copy icon directories (limit to most important ones)
        for size in 16x16 22x22 24x24 32x32 48x48 scalable; do
            if [ -d "$ICON_PATH/$size" ]; then
                mkdir -p "$APPDIR$ICON_PATH/$size"
                cp -r "$ICON_PATH/$size"/* "$APPDIR$ICON_PATH/$size/" 2>/dev/null || true
            fi
        done
    fi
done

# Create fallback SVG for image-missing icon
echo "Creating fallback image-missing.svg..."
SVG_PATH="$APPDIR/usr/share/icons/Adwaita/scalable/status/image-missing.svg"
mkdir -p "$(dirname "$SVG_PATH")"
cat > "$SVG_PATH" << 'EOL'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">
  <rect width="20" height="20" x="2" y="2" fill="none" stroke="#f00" stroke-width="2"/>
  <line x1="5" y1="5" x2="19" y2="19" stroke="#f00" stroke-width="2"/>
  <line x1="19" y1="5" x2="5" y2="19" stroke="#f00" stroke-width="2"/>
</svg>
EOL

# Create a modified AppRun script with proper GTK environment
cat > "$APPDIR/AppRun" << 'EOL'
#!/bin/bash
# Get the directory containing the AppRun script
HERE="$(dirname "$(readlink -f "$0")")"

# Setup crucial GTK environment variables
export PATH="$HERE/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# GDK Pixbuf environment
export GDK_PIXBUF_MODULE_FILE="$HERE/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache"
export GDK_PIXBUF_MODULEDIR="$HERE/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders"

# GTK environment
export GTK_PATH="$HERE/usr/lib/gtk-3.0"
export GTK_DATA_PREFIX="$HERE/usr"
export XDG_DATA_DIRS="$HERE/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Tell GDK to use software rendering - more compatible
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1

# Disable GTK3 overlay scrollbars (they sometimes cause rendering issues)
export GTK_OVERLAY_SCROLLING=0

# Print diagnostic information
echo "Starting Wine Prefix Manager from AppImage..."
echo "AppDir: $HERE"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "GDK_PIXBUF_MODULE_FILE=$GDK_PIXBUF_MODULE_FILE"
echo "XDG_DATA_DIRS=$XDG_DATA_DIRS"

# Attempt to run the application
if [ -f "$HERE/usr/bin/wine_prefix_manager" ] && [ -x "$HERE/usr/bin/wine_prefix_manager" ]; then
    echo "Executing application..."
    "$HERE/usr/bin/wine_prefix_manager" "$@"
else
    echo "ERROR: Application executable not found!"
    find "$HERE" -type f -executable -name "wine_prefix_manager" | sort
    exit 1
fi
EOL

chmod +x "$APPDIR/AppRun"

# List AppDir root contents before running appimagetool
echo "AppDir root contents:"
ls -la "$APPDIR"

# Create AppImage using appimagetool
echo "Creating AppImage..."

# Download appimagetool if needed
if [ ! -f "appimagetool" ]; then
    echo "Downloading appimagetool..."
    wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
    chmod +x appimagetool
fi

# List AppDir contents for debugging
echo "AppDir structure:"
find "$APPDIR" -type f | sort

# Build the AppImage with appstream validation disabled if needed
echo "Running appimagetool..."
./appimagetool -v --no-appstream "$APPDIR" "$RELEASE_DIR/Wine_Prefix_Manager-${VERSION}-x86_64.AppImage" || {
    echo "First attempt failed. Trying with strict validation disabled..."
    ./appimagetool -v --appimage-extract-and-run --no-appstream "$APPDIR" "$RELEASE_DIR/Wine_Prefix_Manager-${VERSION}-x86_64.AppImage"
}

# Create checksum
echo "Creating checksums..."
cd $RELEASE_DIR
sha256sum "${PACKAGE_NAME}.tar.gz" > "${PACKAGE_NAME}.tar.gz.sha256"
if [ -f "Wine_Prefix_Manager-${VERSION}-x86_64.AppImage" ]; then
    sha256sum "Wine_Prefix_Manager-${VERSION}-x86_64.AppImage" > "Wine_Prefix_Manager-${VERSION}-x86_64.AppImage.sha256"
fi
cd ..

echo "Release artifacts created in ${RELEASE_DIR}/ directory:"
ls -la $RELEASE_DIR

echo "Build complete! 🎉"

if [ -f "$RELEASE_DIR/Wine_Prefix_Manager-${VERSION}-x86_64.AppImage" ]; then
    echo ""
    echo "To run the AppImage with detailed logging:"
    echo "  chmod +x $RELEASE_DIR/Wine_Prefix_Manager-${VERSION}-x86_64.AppImage"
    echo "  $RELEASE_DIR/Wine_Prefix_Manager-${VERSION}-x86_64.AppImage"
    
    echo ""
    echo "If you continue to experience issues, try the following:"
    echo "1. Extract the AppImage contents:"
    echo "   $RELEASE_DIR/Wine_Prefix_Manager-${VERSION}-x86_64.AppImage --appimage-extract"
    echo ""
    echo "2. Run the app directly from the extracted directory:"
    echo "   cd squashfs-root && ./AppRun"
    echo ""
    echo "3. Set the following environment variables before running:"
    echo "   export LIBGL_ALWAYS_SOFTWARE=1"
    echo "   export MESA_GL_VERSION_OVERRIDE=3.3"
    echo ""
fi
