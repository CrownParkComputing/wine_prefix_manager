#!/bin/bash

# Wine Prefix Manager - Debug Build and Run Script
# This script helps build and run the application in debug mode for testing

set -e  # Exit on error

# Function to display usage information
show_usage() {
    echo "Wine Prefix Manager - Debug Build and Run Script"
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  -b, --build-only    Build the debug version without running it"
    echo "  -r, --run-only      Run the existing debug build without rebuilding"
    echo "  -c, --clean         Clean the build directory before building"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "With no options, the script will both build and run the application in debug mode."
}

# Parse command line arguments
BUILD=true
RUN=true
CLEAN=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -b|--build-only)
        RUN=false
        shift
        ;;
        -r|--run-only)
        BUILD=false
        shift
        ;;
        -c|--clean)
        CLEAN=true
        shift
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

# Ensure we're in the project directory
if [ ! -f "pubspec.yaml" ]; then
    if [ -f "../pubspec.yaml" ]; then
        cd ..
    else
        echo "Error: This script must be run from the project root directory or the scripts directory!"
        exit 1
    fi
fi

echo "Working directory: $(pwd)"

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning build directory..."
    flutter clean
fi

# Get dependencies and build
if [ "$BUILD" = true ]; then
    echo "Getting dependencies..."
    flutter pub get
    
    echo "Building Linux debug version..."
    flutter build linux --debug
fi

# Run the application if requested
if [ "$RUN" = true ]; then
    echo "Running Wine Prefix Manager in debug mode..."
    flutter run -d linux
fi

echo "Done!"