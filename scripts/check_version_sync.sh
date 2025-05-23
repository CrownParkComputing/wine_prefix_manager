#!/bin/bash

# Version Sync Checker
# Checks if pubspec.yaml version matches the latest git tag
# Usage: ./scripts/check_version_sync.sh [--fix] [--help]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
PUBSPEC_FILE="$PROJECT_ROOT/pubspec.yaml"
FIX_MODE=false
HELP_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_MODE=true
            shift
            ;;
        --help|-h)
            HELP_MODE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Help function
show_help() {
    echo "Version Sync Checker"
    echo ""
    echo "Checks if pubspec.yaml version matches the latest git tag"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --fix     Automatically create a git tag matching pubspec.yaml version"
    echo "  --help    Show this help message"
    echo ""
    echo "Exit codes:"
    echo "  0    Versions are in sync"
    echo "  1    Versions are out of sync"
    echo "  2    Error occurred (file not found, git not available, etc.)"
}

if [ "$HELP_MODE" = true ]; then
    show_help
    exit 0
fi

# Function to extract version from pubspec.yaml
get_pubspec_version() {
    if [ ! -f "$PUBSPEC_FILE" ]; then
        echo -e "${RED}Error: pubspec.yaml not found at $PUBSPEC_FILE${NC}"
        exit 2
    fi
    
    # Extract version using grep and sed
    local version=$(grep "^version:" "$PUBSPEC_FILE" | sed 's/version: *//g' | sed 's/ *#.*//g' | tr -d '"' | tr -d "'")
    
    if [ -z "$version" ]; then
        echo -e "${RED}Error: Could not extract version from pubspec.yaml${NC}"
        exit 2
    fi
    
    echo "$version"
}

# Function to get latest git tag
get_latest_git_tag() {
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Error: git command not found${NC}"
        exit 2
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Not in a git repository${NC}"
        return 1
    fi
    
    # Get the latest tag
    local latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [ -z "$latest_tag" ]; then
        echo -e "${YELLOW}Warning: No git tags found${NC}"
        return 1
    fi
    
    # Remove 'v' prefix if present (e.g., v1.0.0 -> 1.0.0)
    echo "$latest_tag" | sed 's/^v//'
}

# Function to normalize version (remove build info after +)
normalize_version() {
    echo "$1" | sed 's/+.*//'
}

# Function to create git tag
create_git_tag() {
    local version="$1"
    local tag_name="v$version"
    
    echo -e "${BLUE}Creating git tag: $tag_name${NC}"
    
    if git tag -a "$tag_name" -m "Release version $version"; then
        echo -e "${GREEN}✓ Git tag '$tag_name' created successfully${NC}"
        echo -e "${YELLOW}Don't forget to push the tag: git push origin $tag_name${NC}"
    else
        echo -e "${RED}Error: Failed to create git tag${NC}"
        exit 2
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Checking version synchronization...${NC}"
    echo ""
    
    # Get pubspec version
    echo -e "${BLUE}📄 Reading pubspec.yaml version...${NC}"
    PUBSPEC_VERSION=$(get_pubspec_version)
    PUBSPEC_NORMALIZED=$(normalize_version "$PUBSPEC_VERSION")
    echo -e "   Pubspec version: ${YELLOW}$PUBSPEC_VERSION${NC}"
    echo -e "   Normalized: ${YELLOW}$PUBSPEC_NORMALIZED${NC}"
    echo ""
    
    # Get git tag version
    echo -e "${BLUE}🏷️  Checking latest git tag...${NC}"
    if GIT_TAG_VERSION=$(get_latest_git_tag); then
        GIT_NORMALIZED=$(normalize_version "$GIT_TAG_VERSION")
        echo -e "   Latest git tag: ${YELLOW}$GIT_TAG_VERSION${NC}"
        echo -e "   Normalized: ${YELLOW}$GIT_NORMALIZED${NC}"
        echo ""
        
        # Compare versions
        if [ "$PUBSPEC_NORMALIZED" = "$GIT_NORMALIZED" ]; then
            echo -e "${GREEN}✅ Versions are in sync!${NC}"
            echo -e "   Both pubspec.yaml and git tag reference version: ${GREEN}$PUBSPEC_NORMALIZED${NC}"
            exit 0
        else
            echo -e "${RED}❌ Versions are out of sync!${NC}"
            echo -e "   Pubspec version: ${YELLOW}$PUBSPEC_NORMALIZED${NC}"
            echo -e "   Git tag version: ${YELLOW}$GIT_NORMALIZED${NC}"
            echo ""
            
            if [ "$FIX_MODE" = true ]; then
                echo -e "${BLUE}🔧 Fix mode enabled. Creating git tag...${NC}"
                create_git_tag "$PUBSPEC_NORMALIZED"
                exit 0
            else
                echo -e "${YELLOW}💡 Suggestions:${NC}"
                echo -e "   1. Update pubspec.yaml version to match git tag: $GIT_NORMALIZED"
                echo -e "   2. Create new git tag to match pubspec.yaml: v$PUBSPEC_NORMALIZED"
                echo -e "   3. Run with --fix to automatically create the git tag"
                echo ""
                echo -e "${YELLOW}Commands:${NC}"
                echo -e "   Create tag: ${BLUE}git tag -a v$PUBSPEC_NORMALIZED -m \"Release version $PUBSPEC_NORMALIZED\"${NC}"
                echo -e "   Push tag:   ${BLUE}git push origin v$PUBSPEC_NORMALIZED${NC}"
                exit 1
            fi
        fi
    else
        echo -e "   ${YELLOW}No git tags found${NC}"
        echo ""
        
        if [ "$FIX_MODE" = true ]; then
            echo -e "${BLUE}🔧 Fix mode enabled. Creating first git tag...${NC}"
            create_git_tag "$PUBSPEC_NORMALIZED"
            exit 0
        else
            echo -e "${YELLOW}💡 Suggestion:${NC}"
            echo -e "   Create your first git tag: ${BLUE}git tag -a v$PUBSPEC_NORMALIZED -m \"Release version $PUBSPEC_NORMALIZED\"${NC}"
            echo -e "   Then push it: ${BLUE}git push origin v$PUBSPEC_NORMALIZED${NC}"
            echo ""
            echo -e "${YELLOW}Or run with --fix to automatically create the tag${NC}"
            exit 1
        fi
    fi
}

# Run main function
main "$@" 