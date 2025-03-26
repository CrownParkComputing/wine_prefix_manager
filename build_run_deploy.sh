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
APP_VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}')
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
    echo "5) Build and Deploy (User)"
    echo "6) Build and Deploy (System)"
    echo "7) Clean Project"
    echo "q) Quit"
    echo
    echo -n "Select an option: "
}

function build_release() {
    echo -e "${YELLOW}Building release version...${NC}"
    
    # Clean up platform-specific directories
    rm -rf android ios web windows macos
    
    # Clean and get dependencies
    flutter clean
    flutter pub get
    
    # Enable Linux desktop
    flutter config --enable-linux-desktop
    
    # Build release
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
    echo -e "${YELLOW}Deploying application...${NC}"
    
    # Create directories
    mkdir -p "$RELEASE_DIR" "$INSTALL_DIR"
    
    # Package the application
    local PACKAGE_NAME="${PROJECT_NAME}_v${APP_VERSION}_linux_x64"
    local PACKAGE_DIR="$RELEASE_DIR/$PACKAGE_NAME"
    
    # Copy files
    cp -r "$BUILD_DIR"/* "$INSTALL_DIR"
    
    # Create desktop entry
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
    mkdir -p "$HOME/.local/bin"
    ln -sf "$INSTALL_DIR/wine_prefix_manager" "$HOME/.local/bin/wine_prefix_manager"
    
    # Create distributable package
    mkdir -p "$PACKAGE_DIR"
    cp -r "$BUILD_DIR"/* "$PACKAGE_DIR"
    
    # Create archive
    cd "$RELEASE_DIR"
    tar -czf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"
    
    echo -e "${GREEN}Deployment complete!${NC}"
    echo -e "${BLUE}Package created: ${RELEASE_DIR}/${PACKAGE_NAME}.tar.gz${NC}"
}

function deploy_system() {
    echo -e "${YELLOW}Deploying application system-wide...${NC}"
    
    # Check if running with sudo
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}System installation requires root privileges.${NC}"
        echo -e "${YELLOW}Please run with sudo.${NC}"
        return 1
    fi
    
    # Create system directories
    mkdir -p "$SYSTEM_INSTALL_DIR"
    
    # Copy files
    cp -r "$BUILD_DIR"/* "$SYSTEM_INSTALL_DIR"
    
    # Create desktop entry
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
    ln -sf "$SYSTEM_INSTALL_DIR/wine_prefix_manager" "/usr/local/bin/wine_prefix_manager"
    
    echo -e "${GREEN}System-wide deployment complete!${NC}"
}

function clean_project() {
    echo -e "${YELLOW}Cleaning project...${NC}"
    flutter clean
    rm -rf "$RELEASE_DIR"
    
    # Ask about removing installations
    read -p "Remove user installation? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        rm -f "$HOME/.local/share/applications/wine_prefix_manager.desktop"
        rm -f "$HOME/.local/bin/wine_prefix_manager"
    fi
    
    read -p "Remove system installation? (requires sudo) (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm -rf "$SYSTEM_INSTALL_DIR"
        sudo rm -f "/usr/share/applications/wine_prefix_manager.desktop"
        sudo rm -f "/usr/local/bin/wine_prefix_manager"
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
            if [ ! -d "$BUILD_DIR" ]; then
                echo -e "${RED}Build the release version first!${NC}"
            else
                deploy_app
            fi
            ;;
        4)
            if [ ! -d "$BUILD_DIR" ]; then
                echo -e "${RED}Build the release version first!${NC}"
            else
                sudo ./build_run_deploy.sh --system-deploy
            fi
            ;;
        5)
            build_release && deploy_app
            ;;
        6)
            build_release && sudo ./build_run_deploy.sh --system-deploy
            ;;
        7)
            clean_project
            ;;
        q|Q)
            echo -e "${BLUE}Goodbye!${NC}"
            exit 0
            ;;
        --system-deploy)
            # Hidden option for sudo deployment
            deploy_system
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    echo
    read -n1 -p "Press any key to continue..."
done
