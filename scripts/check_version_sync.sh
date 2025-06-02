#!/bin/bash

# Simple version sync checker for Wine Prefix Manager

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PUBSPEC_FILE="$PROJECT_ROOT/pubspec.yaml"

# Parse arguments
FIX_MODE=false
if [[ "$1" == "--fix" ]]; then
    FIX_MODE=true
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Version Sync Checker"
    echo ""
    echo "Usage: $0 [--fix]"
    echo "  --fix    Create git tag to match pubspec.yaml version"
    echo "  --help   Show this help"
    exit 0
fi

# Get version from pubspec.yaml
get_pubspec_version() {
    if [[ ! -f "$PUBSPEC_FILE" ]]; then
        echo -e "${RED}Error: pubspec.yaml not found${NC}"
        exit 2
    fi
    
    grep "^version:" "$PUBSPEC_FILE" | sed 's/version: *//g' | sed 's/+.*//' | tr -d '"' | tr -d "'"
}

# Get latest git tag
get_latest_git_tag() {
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Error: git not found${NC}"
        exit 2
    fi
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Not in a git repository${NC}"
        return 1
    fi
    
    git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || return 1
}

echo -e "${BLUE}Checking version sync...${NC}"

# Get versions
PUBSPEC_VERSION=$(get_pubspec_version)
echo -e "Pubspec version: ${YELLOW}$PUBSPEC_VERSION${NC}"

if GIT_VERSION=$(get_latest_git_tag); then
    echo -e "Git tag version: ${YELLOW}$GIT_VERSION${NC}"
    
    if [[ "$PUBSPEC_VERSION" == "$GIT_VERSION" ]]; then
        echo -e "${GREEN}✅ Versions are in sync!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Versions are out of sync!${NC}"
        
        if [[ "$FIX_MODE" == true ]]; then
            echo -e "${BLUE}Creating git tag v$PUBSPEC_VERSION...${NC}"
            if git tag -a "v$PUBSPEC_VERSION" -m "Release version $PUBSPEC_VERSION"; then
                echo -e "${GREEN}✅ Git tag created${NC}"
                echo -e "${YELLOW}Push with: git push origin v$PUBSPEC_VERSION${NC}"
            else
                echo -e "${RED}❌ Failed to create tag${NC}"
                exit 2
            fi
        else
            echo -e "${YELLOW}Fix with: $0 --fix${NC}"
            exit 1
        fi
    fi
else
    echo -e "Git tag version: ${YELLOW}none${NC}"
    
    if [[ "$FIX_MODE" == true ]]; then
        echo -e "${BLUE}Creating first git tag v$PUBSPEC_VERSION...${NC}"
        if git tag -a "v$PUBSPEC_VERSION" -m "Release version $PUBSPEC_VERSION"; then
            echo -e "${GREEN}✅ Git tag created${NC}"
            echo -e "${YELLOW}Push with: git push origin v$PUBSPEC_VERSION${NC}"
        else
            echo -e "${RED}❌ Failed to create tag${NC}"
            exit 2
        fi
    else
        echo -e "${YELLOW}Create tag with: git tag -a v$PUBSPEC_VERSION -m \"Release version $PUBSPEC_VERSION\"${NC}"
        echo -e "${YELLOW}Or fix with: $0 --fix${NC}"
        exit 1
    fi
fi 