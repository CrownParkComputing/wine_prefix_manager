#!/bin/bash

# Wine Prefix Manager - Dependency Installer Script
# This script helps install all dependencies required by Wine Prefix Manager
# without requiring a full build from source.

set -e  # Exit on error

# Function to display usage information
show_usage() {
    echo "Wine Prefix Manager - Dependency Installer"
    echo "Usage: $0 [--distro DISTRO]"
    echo ""
    echo "Options:"
    echo "  --distro DISTRO    Specify your Linux distribution"
    echo "                     Supported: ubuntu, debian, fedora, arch"
    echo "  -h, --help         Show this help message"
    echo ""
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
        echo "Unable to detect Linux distribution. Please specify with --distro."
        exit 1
    fi
    
    echo "Detected distribution: $DISTRO_ID"
    return 0
}

# Parse command line arguments
DISTRO=""
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --distro)
        DISTRO="$2"
        shift 2
        ;;
        -h|--help)
        show_usage
        exit 0
        ;;
        *)
        echo "Unknown option: $key"
        show_usage
        exit 1
        ;;
    esac
done

# Detect distro if not specified
if [ -z "$DISTRO" ]; then
    detect_distro
    DISTRO=${DISTRO_ID,,}  # Convert to lowercase
fi

echo "Installing dependencies for $DISTRO..."

# Install dependencies based on distribution
case "$DISTRO" in
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
    fedora)
        echo "Installing dependencies for Fedora..."
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
            rpm-build \
            rpmdevtools
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
            base-devel \
            libxext \
            xz
        ;;
    *)
        echo "Unsupported distribution: $DISTRO"
        echo "Please install the following packages manually:"
        echo "- wine (or proton)"
        echo "- zenity"
        echo "- zip/unzip"
        echo "- gtk3 development libraries"
        echo "- And other dependencies for Flutter Linux desktop"
        exit 1
        ;;
esac

echo "Installing Flutter dependencies..."
# Check if Flutter is installed
if command -v flutter >/dev/null 2>&1; then
    echo "Flutter found. Enabling Linux desktop support..."
    flutter config --enable-linux-desktop
    
    # Get Flutter dependencies for the project
    if [ -f "/home/jon/wine_prefix_manager/pubspec.yaml" ]; then
        cd "/home/jon/wine_prefix_manager"
        flutter pub get
    else
        echo "Warning: Could not find project's pubspec.yaml. Skipping Flutter dependencies."
    fi
else
    echo "Flutter not found. Please install Flutter first:"
    echo "Visit: https://flutter.dev/docs/get-started/install/linux"
fi

echo ""
echo "Installation completed!"
echo "For additional dependencies and setup, please refer to the README.md file."
echo ""
