#!/bin/bash

# GitHub Release Creation Script for Wine Prefix Manager
# Creates a GitHub release with AppImage attachment

set -e

# Default values
VERSION=""
REPO_OWNER="CrownParkComputing"
REPO_NAME="wine_prefix_manager"
APPIMAGE_DIR="appimage"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --version VERSION"
            echo "Create a GitHub release with AppImage"
            echo ""
            echo "Options:"
            echo "  --version VERSION  Release version (e.g. 3.5.1)"
            echo "  --help            Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$VERSION" ]; then
    echo "❌ Error: VERSION is required"
    echo "Usage: $0 --version VERSION"
    exit 1
fi

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "❌ Error: Not in a git repository"
    exit 1
fi

# Check if tag exists
if ! git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "❌ Error: Git tag v$VERSION does not exist"
    echo "Create it first with: git tag v$VERSION && git push origin v$VERSION"
    exit 1
fi

# Check if AppImage exists
APPIMAGE_FILE="${APPIMAGE_DIR}/WinePrefixManager-${VERSION}-x86_64.AppImage"
if [ ! -f "$APPIMAGE_FILE" ]; then
    echo "❌ Error: AppImage not found: $APPIMAGE_FILE"
    echo "Build it first with: make appimage"
    exit 1
fi

echo "🚀 Creating GitHub release v$VERSION..."
echo "📦 AppImage: $APPIMAGE_FILE ($(du -h "$APPIMAGE_FILE" | cut -f1))"

# Check if GitHub CLI is installed
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ Error: GitHub CLI (gh) is not installed"
    echo "Install it with: sudo apt install gh"
    echo "Or visit: https://github.com/cli/cli#installation"
    exit 1
fi

# Check if authenticated with GitHub
if ! gh auth status >/dev/null 2>&1; then
    echo "❌ Error: Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi

# Generate release notes
RELEASE_NOTES=$(cat << EOF
# Wine Prefix Manager v${VERSION}

## 🎮 What's New in This Release

### ✨ New Features
- **🎨 Category Management System**: Full visual category management with colors and icons
- **📚 Enhanced Game Library**: Improved organization with category-based grouping
- **🎯 One-Click Category Access**: Category management button in game library toolbar
- **🔄 Legacy Migration**: Automatic migration from old category system

### 🛠️ Improvements
- **ColorCoded Categories**: Each category now has customizable colors and emoji icons
- **Drag & Drop Reordering**: Easily reorganize categories with visual feedback
- **Smart Category Filtering**: Enhanced game filtering and grouping
- **Professional AppImage**: Improved portable distribution with proper icon

### 🐛 Bug Fixes
- Fixed category synchronization between game settings and library
- Improved error handling in category operations
- Enhanced UI responsiveness and dark mode compatibility

## 📦 Installation

### Download & Run
1. Download the AppImage from this release
2. Make it executable: \`chmod +x WinePrefixManager-${VERSION}-x86_64.AppImage\`
3. Run it: \`./WinePrefixManager-${VERSION}-x86_64.AppImage\`

### System Requirements
- Linux x86_64
- GTK3 libraries
- Wine (for managing prefixes)

## 🎯 Quick Start
1. Launch the application
2. Go to Settings → Categories to manage your game categories
3. Or click the 📁 Categories button in the game library toolbar
4. Add, edit, reorder, and customize your categories with colors and icons!

## 🔗 Links
- **Repository**: https://github.com/${REPO_OWNER}/${REPO_NAME}
- **Issues**: https://github.com/${REPO_OWNER}/${REPO_NAME}/issues
- **Documentation**: See README.md in the repository

---
**Full Changelog**: https://github.com/${REPO_OWNER}/${REPO_NAME}/compare/v3.5.0...v${VERSION}
EOF
)

# Create the GitHub release
echo "📝 Creating release on GitHub..."
gh release create "v$VERSION" \
    "$APPIMAGE_FILE#WinePrefixManager-${VERSION}-x86_64.AppImage" \
    --repo "${REPO_OWNER}/${REPO_NAME}" \
    --title "Wine Prefix Manager v${VERSION}" \
    --notes "$RELEASE_NOTES" \
    --latest

echo ""
echo "✅ GitHub release created successfully!"
echo "🔗 Release URL: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/v${VERSION}"
echo "📁 AppImage: WinePrefixManager-${VERSION}-x86_64.AppImage"
echo "📊 Size: $(du -h "$APPIMAGE_FILE" | cut -f1)"
echo ""
echo "🎉 Release v${VERSION} is now live!"