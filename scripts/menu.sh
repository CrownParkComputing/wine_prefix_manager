#!/bin/bash

# Wine Prefix Manager - Build Menu System
# This script provides a menu-driven interface to all build and release operations

# Ensure the script is run from the project root
cd "$(dirname "$0")/.." || exit 1

if [ ! -f "pubspec.yaml" ]; then
    echo "Error: This script must be run from the project root directory!"
    exit 1
fi

# Get current version from pubspec.yaml
VERSION=$(grep 'version:' pubspec.yaml | awk '{print $2}' | tr -d "'")

# Main menu loop
while true; do
    clear
    echo "======================================================"
    echo "       Wine Prefix Manager - Build System v$VERSION"
    echo "======================================================"
    echo
    echo "Build Options:"
    echo "  1. Build for Arch Linux"
    echo "  2. Build for Debian/Ubuntu"
    echo "  3. Build RPM Package"
    echo "  4. Build All Packages"
    echo
    echo "Release Options:"
    echo "  5. Full Release (Build + Version Increment + GitHub + Local Install)"
    echo "  6. GitHub Actions Release (Create Tag Only)"
    echo
    echo "Development Options:"
    echo "  7. Debug Build and Run"
    echo "  8. Clean Build Directories"
    echo "  9. Install Dependencies"
    echo "  10. Install Locally"
    echo
    echo "System:"
    echo "  11. Exit"
    echo
    read -p "Enter your choice [1-11]: " choice
    
    case $choice in
        1)  # Build for Arch Linux
            clear
            echo "Building package for Arch Linux..."
            ./scripts/build_and_release.sh --distro arch --skip-git
            if [ $? -eq 0 ]; then
                echo "Build completed successfully!"
            else
                echo "Build failed!"
            fi
            read -p "Press Enter to continue..."
            ;;
            
        2)  # Build for Debian/Ubuntu
            clear
            echo "Building package for Debian/Ubuntu..."
            ./scripts/build_and_release.sh --distro debian --skip-git
            if [ $? -eq 0 ]; then
                echo "Build completed successfully!"
            else
                echo "Build failed!"
            fi
            read -p "Press Enter to continue..."
            ;;
            
        3)  # Build RPM Package
            clear
            echo "Building RPM package..."
            ./scripts/build_and_release.sh --distro rpm --skip-git
            if [ $? -eq 0 ]; then
                echo "Build completed successfully!"
            else
                echo "Build failed!"
            fi
            read -p "Press Enter to continue..."
            ;;
            
        4)  # Build All Packages
            clear
            echo "Building all packages..."
            ./scripts/build_and_release.sh --distro all --skip-git
            if [ $? -eq 0 ]; then
                echo "Build completed successfully!"
            else
                echo "Build failed!"
            fi
            read -p "Press Enter to continue..."
            ;;
            
        5)  # Full Release
            clear
            echo "Preparing full release..."
            echo "Select release type:"
            echo "1. Major (x.0.0)"
            echo "2. Minor (0.x.0)"
            echo "3. Patch (0.0.x)"
            
            read -p "Enter your choice [1-3]: " release_choice
            
            case $release_choice in
                1) release_type="major" ;;
                2) release_type="minor" ;;
                3) release_type="patch" ;;
                *) 
                    echo "Invalid choice!"
                    read -p "Press Enter to continue..."
                    continue
                    ;;
            esac
            
            clear
            echo "This will:"
            echo "1. Increment the $release_type version"
            echo "2. Build local packages"
            echo "3. Push to GitHub"
            echo "4. Create a GitHub tag to trigger GitHub Actions workflows"
            echo "5. Install the new release locally"
            echo
            echo "Note: The new GitHub Actions workflow will handle the following:"
            echo "- Building .deb packages with correct naming conventions"
            echo "- Building .rpm packages"
            echo "- Building AppImage packages with improved handling of modern libraries"
            echo "- Creating a GitHub release with all packages"
            echo
            read -p "Are you sure you want to continue? [y/N]: " confirm
            
            if [[ $confirm =~ ^[Yy]$ ]]; then
                # Step 1 & 2 & 3: Run the build_and_release script
                echo "Building packages and incrementing version..."
                ./scripts/build_and_release.sh --distro all --release-type $release_type
                if [ $? -ne 0 ]; then
                    echo "Build and release failed!"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                # Get the new version from pubspec.yaml after incrementing
                NEW_VERSION=$(grep 'version:' pubspec.yaml | awk '{print $2}' | tr -d "'")
                echo "New version: $NEW_VERSION"
                
                # Step 4: Create and push tag for GitHub Actions
                echo "Creating and pushing tag v$NEW_VERSION to trigger GitHub Actions workflows..."
                git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"
                git push origin "v$NEW_VERSION"
                
                if [ $? -ne 0 ]; then
                    echo "Failed to push tag v$NEW_VERSION!"
                    read -p "Press Enter to continue..."
                    continue
                fi
                
                echo "GitHub Actions workflows have been triggered."
                echo "You can check the progress at: https://github.com/jon/wine_prefix_manager/actions"
                
                # Step 5: Install locally
                echo "Installing new release locally..."
                echo "Select installation method:"
                echo "1. Install for current user only (~/bin or ~/.local/bin)"
                echo "2. Install system-wide (requires sudo)"
                echo "3. Skip local installation"
                
                read -p "Enter your choice [1-3]: " install_choice
                
                case $install_choice in
                    1)
                        clear
                        echo "Building release version for local installation..."
                        # No need to rebuild if we've already built it
                        # flutter build linux --release
                        
                        # Define paths
                        APP_NAME="wine_prefix_manager"
                        BUILD_DIR="build/linux/x64/release/bundle"
                        LOCAL_BIN="$HOME/.local/bin"
                        LOCAL_APP_DIR="$HOME/.local/share/applications"
                        LOCAL_ICON_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
                        INSTALL_DIR="$HOME/.local/lib/$APP_NAME"
                        
                        # Create directories if they don't exist
                        mkdir -p "$LOCAL_BIN"
                        mkdir -p "$LOCAL_APP_DIR"
                        mkdir -p "$LOCAL_ICON_DIR"
                        mkdir -p "$INSTALL_DIR"
                        
                        # Copy application files
                        echo "Copying application files..."
                        find "$BUILD_DIR" -maxdepth 1 -mindepth 1 -exec cp -r {} "$INSTALL_DIR/" \;
                        
                        # Create launcher script
                        echo "Creating launcher script..."
                        cat > "$LOCAL_BIN/$APP_NAME" <<EOF
#!/bin/bash
exec "$INSTALL_DIR/$APP_NAME" "\$@"
EOF
                        chmod +x "$LOCAL_BIN/$APP_NAME"
                        
                        # Create desktop entry
                        echo "Creating desktop entry..."
                        cat > "$LOCAL_APP_DIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=$APP_NAME
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Utility;
EOF
                        
                        # Copy icon
                        if [ -f "$BUILD_DIR/data/flutter_assets/assets/icon.png" ]; then
                            cp "$BUILD_DIR/data/flutter_assets/assets/icon.png" "$LOCAL_ICON_DIR/$APP_NAME.png"
                        fi
                        
                        echo "Installation completed successfully!"
                        echo "You can run the application by typing '$APP_NAME' in the terminal"
                        echo "or by finding it in your application menu."
                        ;;
                    2)
                        clear
                        echo "Installing system-wide (requires sudo)..."
                        
                        # Define paths
                        APP_NAME="wine_prefix_manager"
                        BUILD_DIR="build/linux/x64/release/bundle"
                        
                        # Create temporary installation script
                        TMP_SCRIPT=$(mktemp)
                        cat > "$TMP_SCRIPT" <<EOF
#!/bin/bash
set -e

# Create directories
mkdir -p /usr/local/lib/$APP_NAME
mkdir -p /usr/local/bin
mkdir -p /usr/share/applications
mkdir -p /usr/share/icons/hicolor/128x128/apps

# Copy application files
find "$(pwd)/$BUILD_DIR" -maxdepth 1 -mindepth 1 -exec cp -r {} /usr/local/lib/$APP_NAME/ \;

# Create launcher script
cat > /usr/local/bin/$APP_NAME <<EOL
#!/bin/bash
exec /usr/local/lib/$APP_NAME/$APP_NAME "\$@"
EOL
chmod +x /usr/local/bin/$APP_NAME

# Create desktop entry
cat > /usr/share/applications/$APP_NAME.desktop <<EOL
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=$APP_NAME
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Utility;
EOL

# Copy icon
if [ -f "$(pwd)/$BUILD_DIR/data/flutter_assets/assets/icon.png" ]; then
    cp "$(pwd)/$BUILD_DIR/data/flutter_assets/assets/icon.png" /usr/share/icons/hicolor/128x128/apps/$APP_NAME.png
fi

echo "System-wide installation completed successfully!"
EOF
                        
                        chmod +x "$TMP_SCRIPT"
                        
                        # Run the script with sudo
                        sudo "$TMP_SCRIPT"
                        
                        # Remove the temporary script
                        rm "$TMP_SCRIPT"
                        ;;
                    3)
                        echo "Skipping local installation."
                        ;;
                    *)
                        echo "Invalid choice! Skipping local installation."
                        ;;
                esac
                
                echo "Full release process completed successfully!"
            else
                echo "Release cancelled."
            fi
            
            read -p "Press Enter to continue..."
            ;;
            
        6)  # GitHub Actions Release
            clear
            echo "GitHub Actions Release"
            echo "This will create a git tag to trigger GitHub Actions workflows."
            
            # Get the current version from pubspec.yaml
            CURRENT_VERSION=$(grep 'version:' pubspec.yaml | awk '{print $2}' | tr -d "'")
            
            echo "Current version in pubspec.yaml: $CURRENT_VERSION"
            echo
            echo "Select release type:"
            echo "1. Use current version ($CURRENT_VERSION)"
            echo "2. Specify a custom version"
            
            read -p "Enter your choice [1-2]: " tag_choice
            
            case $tag_choice in
                1)
                    VERSION_TAG="v$CURRENT_VERSION"
                    ;;
                2)
                    read -p "Enter custom version (without 'v' prefix): " custom_version
                    VERSION_TAG="v$custom_version"
                    ;;
                *)
                    echo "Invalid choice!"
                    read -p "Press Enter to continue..."
                    continue
                    ;;
            esac
            
            echo
            echo "This will create tag $VERSION_TAG and push it to trigger GitHub Actions workflows."
            read -p "Are you sure you want to continue? [y/N]: " confirm
            
            if [[ $confirm =~ ^[Yy]$ ]]; then
                echo "Creating and pushing tag $VERSION_TAG..."
                git tag -a "$VERSION_TAG" -m "Release $VERSION_TAG"
                git push origin "$VERSION_TAG"
                
                if [ $? -eq 0 ]; then
                    echo "Tag $VERSION_TAG pushed successfully!"
                    echo "GitHub Actions workflows have been triggered."
                    echo "You can check the progress at: https://github.com/jon/wine_prefix_manager/actions"
                else
                    echo "Failed to push tag $VERSION_TAG!"
                fi
            else
                echo "Release cancelled."
            fi
            
            read -p "Press Enter to continue..."
            ;;
            
        7)  # Debug Build and Run
            clear
            echo "Debug Build and Run Options:"
            echo "1. Build and Run"
            echo "2. Build Only"
            echo "3. Run Only"
            echo "4. Clean Build"
            echo "5. Return to Main Menu"
            
            read -p "Enter your choice [1-5]: " debug_choice
            
            case $debug_choice in
                1)
                    clear
                    echo "Building and running in debug mode..."
                    ./scripts/debug_build_run.sh
                    ;;
                2)
                    clear
                    echo "Building in debug mode..."
                    ./scripts/debug_build_run.sh --build-only
                    ;;
                3)
                    clear
                    echo "Running existing debug build..."
                    ./scripts/debug_build_run.sh --run-only
                    ;;
                4)
                    clear
                    echo "Cleaning and running debug build..."
                    ./scripts/debug_build_run.sh --clean
                    ;;
                5)
                    continue
                    ;;
                *)
                    echo "Invalid choice!"
                    ;;
            esac
            
            read -p "Press Enter to continue..."
            ;;
            
        7)  # Clean Build Directories
            clear
            echo "Cleaning build directories..."
            
            rm -rf build/
            rm -rf .dart_tool/
            rm -f .flutter-plugins
            rm -f .flutter-plugins-dependencies
            
            echo "Build directories cleaned!"
            read -p "Press Enter to continue..."
            ;;
            
        8)  # Install Dependencies
            clear
            echo "Detecting your distribution..."
            
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                DISTRO=${ID,,}  # Convert to lowercase
                echo "Detected distribution: $DISTRO"
            else
                echo "Could not auto-detect your distribution."
                echo "Please select your distribution:"
                echo "1. Ubuntu/Debian"
                echo "2. Arch Linux/Manjaro"
                echo "3. Fedora"
                echo "4. Other"
                
                read -p "Enter your choice [1-4]: " distro_choice
                
                case $distro_choice in
                    1) DISTRO="ubuntu" ;;
                    2) DISTRO="arch" ;;
                    3) DISTRO="fedora" ;;
                    4) DISTRO="other" ;;
                    *) 
                        echo "Invalid choice!"
                        read -p "Press Enter to continue..."
                        continue
                        ;;
                esac
            fi
            
            echo "Installing dependencies for $DISTRO..."
            ./scripts/install_dependencies.sh --distro "$DISTRO"
            
            read -p "Press Enter to continue..."
            ;;
            
        9)  # Install Locally
            clear
            echo "Installing Wine Prefix Manager locally..."
            echo "This will build and install the application to your local system."
            echo
            echo "Select installation method:"
            echo "1. Install for current user only (~/bin or ~/.local/bin)"
            echo "2. Install system-wide (requires sudo)"
            echo "3. Return to Main Menu"
            
            read -p "Enter your choice [1-3]: " install_choice
            
            case $install_choice in
                1)
                    clear
                    echo "Building release version..."
                    flutter build linux --release
                    
                    # Define paths
                    APP_NAME="wine_prefix_manager"
                    BUILD_DIR="build/linux/x64/release/bundle"
                    LOCAL_BIN="$HOME/.local/bin"
                    LOCAL_APP_DIR="$HOME/.local/share/applications"
                    LOCAL_ICON_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
                    INSTALL_DIR="$HOME/.local/lib/$APP_NAME"
                    
                    # Create directories if they don't exist
                    mkdir -p "$LOCAL_BIN"
                    mkdir -p "$LOCAL_APP_DIR"
                    mkdir -p "$LOCAL_ICON_DIR"
                    mkdir -p "$INSTALL_DIR"
                    
                    # Copy application files
                    echo "Copying application files..."
                    find "$BUILD_DIR" -maxdepth 1 -mindepth 1 -exec cp -r {} "$INSTALL_DIR/" \;
                    
                    # Create launcher script
                    echo "Creating launcher script..."
                    cat > "$LOCAL_BIN/$APP_NAME" <<EOF
#!/bin/bash
exec "$INSTALL_DIR/$APP_NAME" "\$@"
EOF
                    chmod +x "$LOCAL_BIN/$APP_NAME"
                    
                    # Create desktop entry
                    echo "Creating desktop entry..."
                    cat > "$LOCAL_APP_DIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=$APP_NAME
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Utility;
EOF
                    
                    # Copy icon
                    if [ -f "$BUILD_DIR/data/flutter_assets/assets/icon.png" ]; then
                        cp "$BUILD_DIR/data/flutter_assets/assets/icon.png" "$LOCAL_ICON_DIR/$APP_NAME.png"
                    fi
                    
                    echo "Installation completed successfully!"
                    echo "You may need to add $LOCAL_BIN to your PATH if it's not already there."
                    echo "You can run the application by typing '$APP_NAME' in the terminal"
                    echo "or by finding it in your application menu."
                    ;;
                2)
                    clear
                    echo "Building release version..."
                    flutter build linux --release
                    
                    # Define paths
                    APP_NAME="wine_prefix_manager"
                    BUILD_DIR="build/linux/x64/release/bundle"
                    INSTALL_DIR="/usr/local/lib/$APP_NAME"
                    
                    echo "Installing system-wide (requires sudo)..."
                    
                    # Create temporary installation script
                    TMP_SCRIPT=$(mktemp)
                    cat > "$TMP_SCRIPT" <<EOF
#!/bin/bash
set -e

# Create directories
mkdir -p /usr/local/lib/$APP_NAME
mkdir -p /usr/local/bin
mkdir -p /usr/share/applications
mkdir -p /usr/share/icons/hicolor/128x128/apps

# Copy application files
find "$(pwd)/$BUILD_DIR" -maxdepth 1 -mindepth 1 -exec cp -r {} /usr/local/lib/$APP_NAME/ \;

# Create launcher script
cat > /usr/local/bin/$APP_NAME <<EOL
#!/bin/bash
exec /usr/local/lib/$APP_NAME/$APP_NAME "\$@"
EOL
chmod +x /usr/local/bin/$APP_NAME

# Create desktop entry
cat > /usr/share/applications/$APP_NAME.desktop <<EOL
[Desktop Entry]
Name=Wine Prefix Manager
Comment=Manage Wine prefixes
Exec=$APP_NAME
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Utility;
EOL

# Copy icon
if [ -f "$(pwd)/$BUILD_DIR/data/flutter_assets/assets/icon.png" ]; then
    cp "$(pwd)/$BUILD_DIR/data/flutter_assets/assets/icon.png" /usr/share/icons/hicolor/128x128/apps/$APP_NAME.png
fi

echo "System-wide installation completed successfully!"
EOF
                    
                    chmod +x "$TMP_SCRIPT"
                    
                    # Run the script with sudo
                    sudo "$TMP_SCRIPT"
                    
                    # Remove the temporary script
                    rm "$TMP_SCRIPT"
                    ;;
                3)
                    continue
                    ;;
                *)
                    echo "Invalid choice!"
                    ;;
            esac
            
            read -p "Press Enter to continue..."
            ;;
            
        10)  # Exit
            clear
            echo "Thank you for using Wine Prefix Manager Build System!"
            exit 0
            ;;
            
        *)  # Invalid choice
            echo "Invalid choice. Please try again."
            sleep 2
            ;;
    esac
done
