#!/bin/bash

# Set colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project variables
PROJECT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_NAME=$(basename "$PROJECT_DIR")
# Ensure APP_VERSION is fetched correctly, handle potential errors
APP_VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}')
if [ -z "$APP_VERSION" ]; then
    echo -e "${RED}Error: Could not determine app version from pubspec.yaml.${NC}"
    exit 1
fi
BUILD_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
RELEASE_DIR="$PROJECT_DIR/dist"
INSTALL_DIR="$HOME/.local/share/wine_prefix_manager"
SYSTEM_INSTALL_DIR="/opt/wine_prefix_manager"

function show_menu() {
    clear
    echo -e "${BLUE}=== Wine Prefix Manager - Development Tools ===${NC}"
    echo "1) Build Release"
    echo "2) Run Development Version"
    echo "3) Deploy Application (User)"
    echo "4) Deploy Application (System)"
    echo "5) Build and Create Zip"
    echo "6) Build, Deploy (System), and Create Zip"
    echo "7) Clean Project"
    echo "8) Create Git Release (Tag, Build, Zip)" # New option
    echo "q) Quit"
    echo
    echo -n "Select an option: "
}

function build_release() {
    echo -e "${YELLOW}Building release version...${NC}"

    # Clean and get dependencies
    echo "Running flutter clean..."
    flutter clean
    echo "Running flutter pub get..."
    flutter pub get

    # Build release
    echo "Running flutter build linux --release..."
    if flutter build linux --release; then
        echo -e "${GREEN}Build successful!${NC}"
        return 0
    else
        echo -e "${RED}Build failed!${NC}"
        return 1
    fi
}

function run_dev() {
    echo -e "${YELLOW}Running development version...${NC}"
    flutter run -d linux
}

function deploy_app() {
    echo -e "${YELLOW}Deploying application (User)...${NC}"

    if [ ! -d "$BUILD_DIR" ]; then
        echo -e "${RED}Build directory not found. Build the release version first!${NC}"
        return 1
    fi

    # Create directories
    mkdir -p "$INSTALL_DIR"

    # Copy files
    echo "Copying build files to $INSTALL_DIR..."
    cp -r "$BUILD_DIR"/* "$INSTALL_DIR"

    # Create desktop entry
    echo "Creating desktop entry..."
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/wine_prefix_manager.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Wine Prefix Manager
Comment=Manage Wine prefixes on Linux
Exec=$INSTALL_DIR/wine_prefix_manager
Icon=$INSTALL_DIR/data/flutter_assets/assets/icon.png
Terminal=false
Categories=Utility;Development;
EOF

    # Create symlink
    echo "Creating symlink in $HOME/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    ln -sf "$INSTALL_DIR/wine_prefix_manager" "$HOME/.local/bin/wine_prefix_manager"

    echo -e "${GREEN}User deployment complete!${NC}"
    echo -e "${BLUE}Run using 'wine_prefix_manager' or find it in your application menu.${NC}"
    return 0
}

function deploy_system() {
    echo -e "${YELLOW}Deploying application system-wide...${NC}"

    # Check if running with sudo
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}System installation requires root privileges.${NC}"
        echo -e "${YELLOW}Please run the script with sudo for this option.${NC}"
        return 1
    fi

    if [ ! -d "$BUILD_DIR" ]; then
        echo -e "${RED}Build directory not found. Build the release version first!${NC}"
        return 1
    fi

    # Remove existing installation first
    echo -e "${YELLOW}Removing previous system installation (if any)...${NC}"
    rm -rf "$SYSTEM_INSTALL_DIR"

    # Create system directories
    echo -e "${YELLOW}Creating installation directory $SYSTEM_INSTALL_DIR...${NC}"
    mkdir -p "$SYSTEM_INSTALL_DIR"

    # Copy files
    echo "Copying build files to $SYSTEM_INSTALL_DIR..."
    cp -r "$BUILD_DIR"/* "$SYSTEM_INSTALL_DIR"

    # Create desktop entry
    echo "Creating desktop entry in /usr/share/applications..."
    cat > "/usr/share/applications/wine_prefix_manager.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Wine Prefix Manager
Comment=Manage Wine prefixes on Linux
Exec=$SYSTEM_INSTALL_DIR/wine_prefix_manager
Icon=$SYSTEM_INSTALL_DIR/data/flutter_assets/assets/icon.png
Terminal=false
Categories=Utility;Development;
EOF

    # Create symlink
    echo "Creating symlink in /usr/local/bin..."
    ln -sf "$SYSTEM_INSTALL_DIR/wine_prefix_manager" "/usr/local/bin/wine_prefix_manager"

    echo -e "${GREEN}System-wide deployment complete!${NC}"
    return 0
}

function create_zip() {
    echo -e "${YELLOW}Creating release zip archive...${NC}"

    # Ensure release is built
    if [ ! -d "$BUILD_DIR" ]; then
        echo -e "${RED}Release build not found. Cannot create zip.${NC}"
        return 1
    fi

    local ZIP_NAME="${PROJECT_NAME}_v${APP_VERSION}_linux_x64.zip"
    local ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

    # Create release directory if it doesn't exist
    mkdir -p "$RELEASE_DIR"

    # Create zip archive
    echo "Creating archive at $ZIP_PATH..."
    # Use subshell to change directory temporarily
    if (cd "$BUILD_DIR" && zip -qr "$ZIP_PATH" .); then
        echo -e "${GREEN}Zip archive created successfully: $ZIP_PATH${NC}"
        return 0
    else
        echo -e "${RED}Failed to create zip archive!${NC}"
        return 1
    fi
}

function create_git_release() {
    echo -e "${YELLOW}Creating Git release and zip archive...${NC}"

    # 1. Check Git status
    echo "Checking Git status..."
    if ! git diff --quiet || ! git diff --staged --quiet; then
        echo -e "${RED}Error: Uncommitted changes detected. Please commit or stash changes before creating a release.${NC}"
        git status --short # Show changes
        return 1
    fi
    echo -e "${GREEN}Git working directory is clean.${NC}"

    # 2. Define and check tag
    local TAG_NAME="v${APP_VERSION}"
    echo "Checking for existing tag: $TAG_NAME..."
    if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
        echo -e "${RED}Error: Tag '$TAG_NAME' already exists.${NC}"
        return 1
    fi
    echo -e "${GREEN}Tag '$TAG_NAME' does not exist.${NC}"

    # 3. Create Git tag
    echo "Creating Git tag: $TAG_NAME..."
    if ! git tag -a "$TAG_NAME" -m "Release $TAG_NAME"; then
        echo -e "${RED}Error: Failed to create Git tag '$TAG_NAME'.${NC}"
        return 1
    fi
    echo -e "${GREEN}Git tag '$TAG_NAME' created successfully.${NC}"

    # 4. Ask to push tag (Optional)
    read -p "Push tag '$TAG_NAME' to remote 'origin'? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Pushing tag '$TAG_NAME'..."
        if ! git push origin "$TAG_NAME"; then
            echo -e "${YELLOW}Warning: Failed to push tag '$TAG_NAME'. Please push manually.${NC}"
            # Continue with build anyway
        else
            echo -e "${GREEN}Tag '$TAG_NAME' pushed successfully.${NC}"
        fi
    fi

    # 5. Build Release
    if ! build_release; then
        echo -e "${RED}Build failed. Release process aborted.${NC}"
        # Optional: Consider deleting the local tag if build fails?
        # git tag -d "$TAG_NAME"
        return 1
    fi

    # 6. Create Zip
    if ! create_zip; then
        echo -e "${RED}Zip creation failed. Release process incomplete.${NC}"
        return 1
    fi

    echo -e "${GREEN}Git release process completed successfully!${NC}"
    return 0
}

function clean_project() {
    echo -e "${YELLOW}Cleaning project...${NC}"
    flutter clean
    rm -rf "$RELEASE_DIR"

    # Ask about removing installations
    read -p "Remove user installation? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing user installation..."
        rm -rf "$INSTALL_DIR"
        rm -f "$HOME/.local/share/applications/wine_prefix_manager.desktop"
        rm -f "$HOME/.local/bin/wine_prefix_manager"
    fi

    read -p "Remove system installation? (requires sudo) (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ "$EUID" -ne 0 ]; then
             echo -e "${YELLOW}Sudo required. Please run 'sudo $0' and choose clean again, or manually remove:${NC}"
             echo "  sudo rm -rf \"$SYSTEM_INSTALL_DIR\""
             echo "  sudo rm -f \"/usr/share/applications/wine_prefix_manager.desktop\""
             echo "  sudo rm -f \"/usr/local/bin/wine_prefix_manager\""
        else
            echo "Removing system installation..."
            rm -rf "$SYSTEM_INSTALL_DIR"
            rm -f "/usr/share/applications/wine_prefix_manager.desktop"
            rm -f "/usr/local/bin/wine_prefix_manager"
        fi
    fi

    echo -e "${GREEN}Project cleaned!${NC}"
}

# Main loop
while true; do
    show_menu
    read -n1 choice
    echo
    case $choice in
        1)
            build_release
            ;;
        2)
            run_dev
            ;;
        3)
            deploy_app # Needs build first, checked inside function
            ;;
        4) # Deploy System
            deploy_system # Needs build first, checked inside function. Sudo check also inside.
            ;;
        5)
            build_release && create_zip # Changed deploy_app to create_zip
            ;;
        6) # Build, Deploy System, and Create Zip
            if build_release; then
                 # Sudo check is inside deploy_system
                deploy_system && create_zip # Also create zip after successful system deploy
            fi
            ;;
        7)
            clean_project
            ;;
        8)
            create_git_release
            ;;
        q|Q)
            echo -e "${BLUE}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    echo
    read -n1 -p "Press any key to continue..."
done
