#!/bin/bash

# Build script that handles environment variables for Wine Prefix Manager
# This script ensures IGDB credentials are available during build without committing them to git

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required environment variables are set
check_env_vars() {
    print_status "Checking environment variables..."
    
    if [[ -z "$IGDB_CLIENT_ID" ]]; then
        print_error "IGDB_CLIENT_ID environment variable is not set"
        print_error "Please set it with: export IGDB_CLIENT_ID=your_client_id"
        exit 1
    fi
    
    if [[ -z "$IGDB_CLIENT_SECRET" ]]; then
        print_error "IGDB_CLIENT_SECRET environment variable is not set"
        print_error "Please set it with: export IGDB_CLIENT_SECRET=your_client_secret"
        exit 1
    fi
    
    print_success "Environment variables are set"
}

# Create temporary .env file for build
create_build_env() {
    print_status "Creating temporary .env file for build..."
    
    cat > .env << EOF
IGDB_CLIENT_ID=$IGDB_CLIENT_ID
IGDB_CLIENT_SECRET=$IGDB_CLIENT_SECRET
EOF
    
    print_success "Temporary .env file created"
}

# Clean up temporary files
cleanup() {
    print_status "Cleaning up temporary files..."
    if [[ -f ".env" ]]; then
        rm -f .env
        print_success "Temporary .env file removed"
    fi
}

# Trap to ensure cleanup happens even if script fails
trap cleanup EXIT

# Main execution
main() {
    print_status "Starting build with environment variables..."
    
    # Check environment variables
    check_env_vars
    
    # Create temporary .env file
    create_build_env
    
    # Run the main build script
    print_status "Running main build script..."
    if [[ $# -eq 0 ]]; then
        print_error "Please specify version type: patch, minor, or major"
        exit 1
    fi
    
    ./build_and_release.sh "$@"
    
    print_success "Build completed successfully!"
}

# Show usage if no arguments
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [patch|minor|major]"
    echo ""
    echo "This script builds Wine Prefix Manager with environment variables."
    echo "Make sure to set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET before running."
    echo ""
    echo "Example:"
    echo "  export IGDB_CLIENT_ID=your_client_id"
    echo "  export IGDB_CLIENT_SECRET=your_client_secret"
    echo "  $0 patch"
    exit 1
fi

# Run main function
main "$@" 