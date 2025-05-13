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
    echo "  5. Full Release (Build + Version Increment + GitHub)"
    echo
    echo "Development Options:"
    echo "  6. Debug Build and Run"
    echo "  7. Clean Build Directories"
    echo "  8. Install Dependencies"
    echo
    echo "System:"
    echo "  9. Exit"
    echo
    read -p "Enter your choice [1-9]: " choice
    
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
            echo "This will increment the $release_type version and push to GitHub."
            read -p "Are you sure you want to continue? [y/N]: " confirm
            
            if [[ $confirm =~ ^[Yy]$ ]]; then
                ./scripts/build_and_release.sh --distro all --release-type $release_type
                if [ $? -eq 0 ]; then
                    echo "Release completed successfully!"
                else
                    echo "Release failed!"
                fi
            else
                echo "Release cancelled."
            fi
            
            read -p "Press Enter to continue..."
            ;;
            
        6)  # Debug Build and Run
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
            
        9)  # Exit
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
