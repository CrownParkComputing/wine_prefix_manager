#!/bin/bash

# GitHub Release Creator for Wine Prefix Manager
# Creates a GitHub release and uploads the AppImage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
VERSION=""
GITHUB_TOKEN=""
REPO_OWNER="CrownParkComputing"
REPO_NAME="wine_prefix_manager"
PRERELEASE=false
DRAFT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        --prerelease)
            PRERELEASE=true
            shift
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Help function
show_help() {
    echo "GitHub Release Creator for Wine Prefix Manager"
    echo ""
    echo "Usage: $0 --version VERSION [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  --version VERSION    Release version (e.g., 3.1.0)"
    echo ""
    echo "Options:"
    echo "  --token TOKEN        GitHub token (or set GITHUB_TOKEN env var)"
    echo "  --prerelease         Mark as pre-release"
    echo "  --draft              Create as draft"
    echo "  --help               Show this help"
    echo ""
    echo "Environment variables:"
    echo "  GITHUB_TOKEN         GitHub personal access token"
    echo ""
    echo "Example:"
    echo "  $0 --version 3.1.0"
    echo "  $0 --version 3.1.0 --prerelease"
}

# Validate inputs
validate_inputs() {
    if [ -z "$VERSION" ]; then
        echo -e "${RED}❌ Version is required. Use --version VERSION${NC}"
        exit 1
    fi
    
    # Get token from environment if not provided
    if [ -z "$GITHUB_TOKEN" ] && [ -n "$GITHUB_TOKEN_ENV" ]; then
        GITHUB_TOKEN="$GITHUB_TOKEN_ENV"
    fi
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED}❌ GitHub token is required. Set GITHUB_TOKEN environment variable or use --token${NC}"
        echo -e "${YELLOW}💡 Create a token at: https://github.com/settings/tokens${NC}"
        exit 1
    fi
    
    # Check if git tag exists
    if ! git rev-parse "v$VERSION" >/dev/null 2>&1; then
        echo -e "${RED}❌ Git tag v$VERSION does not exist${NC}"
        echo -e "${YELLOW}💡 Create the tag first: git tag -a v$VERSION -m \"Release version $VERSION\"${NC}"
        exit 1
    fi
    
    # Check if AppImage exists
    APPIMAGE_FILE="$PROJECT_ROOT/appimage/WinePrefixManager-$VERSION-x86_64.AppImage"
    if [ ! -f "$APPIMAGE_FILE" ]; then
        echo -e "${RED}❌ AppImage not found: $APPIMAGE_FILE${NC}"
        echo -e "${YELLOW}💡 Build the AppImage first: make appimage${NC}"
        exit 1
    fi
}

# Generate release notes
generate_release_notes() {
    echo -e "${BLUE}📝 Generating release notes...${NC}"
    
    # Get the previous tag
    PREV_TAG=$(git describe --tags --abbrev=0 "v$VERSION"^ 2>/dev/null || echo "")
    
    cat > "$PROJECT_ROOT/release_notes.md" << EOF
# Wine Prefix Manager v$VERSION

## What's New

### ✨ Enhanced Game Management
- 🎮 **Improved Game Cards**: Redesigned game cards with corner-positioned action icons
- 🖼️ **Image Carousel**: Interactive image viewer with cover art and screenshots
- 🔍 **Detailed Game Info**: Comprehensive game information in dedicated modals
- ⚙️ **Advanced Settings**: Per-game configuration with launch options and categories

### 🔧 Technical Improvements
- 📱 **Better UX**: Enhanced mouse and touch interactions
- 🎨 **Visual Polish**: Improved tooltips, gradients, and visual feedback
- 🖱️ **Mouse Support**: Mouse wheel scrolling for image carousels
- 📊 **Play Time Tracking**: Enhanced play time display and formatting

### 🛠️ Development & Release Management
- ✅ **Version Sync**: Automated version synchronization between pubspec.yaml and git tags
- 🔄 **CI/CD Integration**: GitHub Actions for version checking and release automation
- 📦 **AppImage Support**: Portable Linux distribution format
- 🧰 **Developer Tools**: Enhanced Makefile with comprehensive build targets

### 🐛 Bug Fixes
- Fixed icon interaction issues on game cards
- Improved error handling for missing game metadata
- Enhanced scroll behavior in various UI components
- Better image loading and fallback handling

## Download

- **Linux AppImage**: \`WinePrefixManager-$VERSION-x86_64.AppImage\`
  - Portable, no installation required
  - Compatible with most Linux distributions
  - Simply download, make executable, and run

## Installation

### AppImage (Recommended)
1. Download \`WinePrefixManager-$VERSION-x86_64.AppImage\`
2. Make it executable: \`chmod +x WinePrefixManager-$VERSION-x86_64.AppImage\`
3. Run: \`./WinePrefixManager-$VERSION-x86_64.AppImage\`

### From Source
\`\`\`bash
git clone https://github.com/$REPO_OWNER/$REPO_NAME.git
cd $REPO_NAME
git checkout v$VERSION
flutter pub get
flutter build linux
\`\`\`

## System Requirements

- Linux x86_64
- Wine (for running Windows games)
- GTK 3.0+ (usually pre-installed)

## Changelog
EOF

    if [ -n "$PREV_TAG" ]; then
        echo "" >> "$PROJECT_ROOT/release_notes.md"
        echo "### Commits since $PREV_TAG:" >> "$PROJECT_ROOT/release_notes.md"
        echo "" >> "$PROJECT_ROOT/release_notes.md"
        git log --pretty=format:"- %s (%h)" "$PREV_TAG"..v"$VERSION" >> "$PROJECT_ROOT/release_notes.md"
    fi
    
    echo "" >> "$PROJECT_ROOT/release_notes.md"
    echo "---" >> "$PROJECT_ROOT/release_notes.md"
    echo "" >> "$PROJECT_ROOT/release_notes.md"
    echo "**Full Changelog**: https://github.com/$REPO_OWNER/$REPO_NAME/compare/${PREV_TAG:-$(git rev-list --max-parents=0 HEAD)}...v$VERSION" >> "$PROJECT_ROOT/release_notes.md"
    
    echo -e "${GREEN}✅ Release notes generated${NC}"
}

# Create GitHub release
create_release() {
    echo -e "${BLUE}🚀 Creating GitHub release...${NC}"
    
    # Create the release
    RELEASE_DATA=$(cat << EOF
{
  "tag_name": "v$VERSION",
  "target_commitish": "main",
  "name": "Wine Prefix Manager v$VERSION",
  "body": $(cat "$PROJECT_ROOT/release_notes.md" | jq -R -s .),
  "draft": $DRAFT,
  "prerelease": $PRERELEASE
}
EOF
)

    RELEASE_RESPONSE=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "$RELEASE_DATA" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases")
    
    # Extract release ID
    RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')
    
    if [ "$RELEASE_ID" = "null" ] || [ -z "$RELEASE_ID" ]; then
        echo -e "${RED}❌ Failed to create release${NC}"
        echo "$RELEASE_RESPONSE" | jq .
        exit 1
    fi
    
    echo -e "${GREEN}✅ Release created with ID: $RELEASE_ID${NC}"
    
    # Upload AppImage
    echo -e "${BLUE}📦 Uploading AppImage...${NC}"
    
    UPLOAD_URL="https://uploads.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/$RELEASE_ID/assets"
    ASSET_NAME="WinePrefixManager-$VERSION-x86_64.AppImage"
    
    curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$APPIMAGE_FILE" \
        "$UPLOAD_URL?name=$ASSET_NAME" > /dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ AppImage uploaded successfully${NC}"
    else
        echo -e "${RED}❌ Failed to upload AppImage${NC}"
        exit 1
    fi
    
    # Clean up
    rm -f "$PROJECT_ROOT/release_notes.md"
    
    # Show release URL
    RELEASE_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/v$VERSION"
    echo ""
    echo -e "${GREEN}🎉 Release v$VERSION created successfully!${NC}"
    echo -e "${BLUE}🔗 Release URL: $RELEASE_URL${NC}"
    echo ""
    echo -e "${YELLOW}📋 Next steps:${NC}"
    echo -e "   1. Review the release on GitHub"
    echo -e "   2. Test the uploaded AppImage"
    echo -e "   3. Share the release with users"
}

# Main execution
main() {
    echo -e "${BLUE}🍷 Wine Prefix Manager GitHub Release Creator${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    
    validate_inputs
    generate_release_notes
    create_release
}

# Check for required tools
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}❌ curl is required but not installed${NC}"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}❌ jq is required but not installed${NC}"
    echo -e "${YELLOW}💡 Install jq: sudo pacman -S jq${NC}"
    exit 1
fi

# Show help if no arguments
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# Run main function
main "$@" 