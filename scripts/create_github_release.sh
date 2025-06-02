#!/bin/bash

# Simple GitHub Release Creator for Wine Prefix Manager

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
REPO_OWNER="CrownParkComputing"
REPO_NAME="wine_prefix_manager"

# Parse arguments
if [[ "$1" == "--version" ]]; then
    VERSION="$2"
else
    echo -e "${RED}Usage: $0 --version VERSION${NC}"
    echo "Example: $0 --version 3.3.1"
    exit 1
fi

if [[ -z "$VERSION" ]]; then
    echo -e "${RED}Version required${NC}"
    exit 1
fi

# Check for GitHub token
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo -e "${RED}GITHUB_TOKEN environment variable required${NC}"
    echo "Get a token from: https://github.com/settings/tokens"
    exit 1
fi

PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
APPIMAGE_FILE="$PROJECT_ROOT/appimage/WinePrefixManager-$VERSION-x86_64.AppImage"

# Check if AppImage exists
if [[ ! -f "$APPIMAGE_FILE" ]]; then
    echo -e "${RED}AppImage not found: $APPIMAGE_FILE${NC}"
    echo "Build it first with: make appimage"
    exit 1
fi

# Check if git tag exists
if ! git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo -e "${RED}Git tag v$VERSION does not exist${NC}"
    echo "Create it first with: git tag -a v$VERSION -m \"Release v$VERSION\""
    exit 1
fi

echo -e "${BLUE}Creating GitHub release v$VERSION...${NC}"

# Create simple release notes
RELEASE_NOTES="Release v$VERSION

Download the AppImage below and run:
\`\`\`bash
chmod +x WinePrefixManager-$VERSION-x86_64.AppImage
./WinePrefixManager-$VERSION-x86_64.AppImage
\`\`\`

## Changes
$(git log --pretty=format:"- %s" $(git describe --tags --abbrev=0 v$VERSION^ 2>/dev/null || git rev-list --max-parents=0 HEAD)..v$VERSION || echo "- Initial release")

## System Requirements
- Linux x86_64
- Wine (for running Windows applications)
- GTK 3.0+ (usually pre-installed)"

# Create release using GitHub API
echo -e "${BLUE}Creating release on GitHub...${NC}"
RELEASE_RESPONSE=$(curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases" \
  -d "{
    \"tag_name\": \"v$VERSION\",
    \"name\": \"Wine Prefix Manager v$VERSION\",
    \"body\": $(echo "$RELEASE_NOTES" | jq -R -s .),
    \"draft\": false,
    \"prerelease\": false
  }")

# Extract upload URL
UPLOAD_URL=$(echo "$RELEASE_RESPONSE" | grep -o '"upload_url": "[^"]*' | sed 's/"upload_url": "//' | sed 's/{?name,label}//')

if [[ -z "$UPLOAD_URL" ]]; then
    echo -e "${RED}Failed to create release${NC}"
    echo "$RELEASE_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✅ Release created${NC}"

# Upload AppImage
echo -e "${BLUE}Uploading AppImage...${NC}"
APPIMAGE_NAME="WinePrefixManager-$VERSION-x86_64.AppImage"

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$APPIMAGE_FILE" \
  "$UPLOAD_URL?name=$APPIMAGE_NAME&label=$APPIMAGE_NAME"

echo -e "${GREEN}✅ AppImage uploaded${NC}"
echo -e "${GREEN}🎉 Release v$VERSION created successfully!${NC}"
echo -e "${BLUE}View at: https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/v$VERSION${NC}" 