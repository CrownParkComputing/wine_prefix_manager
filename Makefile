# Wine Prefix Manager - Makefile

.PHONY: help version-check version-fix version-info build clean test format lint install appimage github-release

# Default target
help:
	@echo "Wine Prefix Manager - Available commands:"
	@echo ""
	@echo "Version Management:"
	@echo "  version-check    Check if pubspec.yaml version matches git tags"
	@echo "  version-fix      Auto-create git tag to match pubspec.yaml version"
	@echo "  version-info     Show current version information"
	@echo ""
	@echo "Development:"
	@echo "  build           Build the Flutter application"
	@echo "  clean           Clean build artifacts"
	@echo "  test            Run tests"
	@echo "  format          Format Dart code"
	@echo "  lint            Run linter (dart analyze)"
	@echo "  install         Get Flutter dependencies"
	@echo ""
	@echo "Distribution:"
	@echo "  appimage        Build AppImage for distribution"
	@echo "  github-release  Create GitHub release with AppImage (requires VERSION=x.y.z)"
	@echo "  release-all     Complete release workflow (tag + AppImage + GitHub)"
	@echo ""
	@echo "Release Management:"
	@echo "  tag-release     Create and push a release tag (requires VERSION=x.y.z)"
	@echo ""

# Version management targets
version-check:
	@echo "🔍 Checking version synchronization..."
	@./scripts/check_version_sync.sh

version-fix:
	@echo "🔧 Auto-fixing version synchronization..."
	@./scripts/check_version_sync.sh --fix

version-info:
	@echo "📋 Current version information:"
	@echo "  Pubspec version: $$(grep '^version:' pubspec.yaml | sed 's/version: *//g' | tr -d '"' | tr -d "'")"
	@echo "  Latest git tag:  $$(git describe --tags --abbrev=0 2>/dev/null || echo 'none')"
	@echo "  Current commit:  $$(git rev-parse --short HEAD 2>/dev/null || echo 'not a git repo')"
	@echo "  Branch:          $$(git branch --show-current 2>/dev/null || echo 'not a git repo')"

# Flutter development targets
build:
	@echo "🏗️  Building Flutter application..."
	@flutter build linux

clean:
	@echo "🧹 Cleaning build artifacts..."
	@flutter clean
	@rm -rf appimage/

test:
	@echo "🧪 Running tests..."
	@flutter test

format:
	@echo "✨ Formatting Dart code..."
	@dart format .

lint:
	@echo "🔍 Running linter..."
	@dart analyze

install:
	@echo "📦 Getting Flutter dependencies..."
	@flutter pub get

# Distribution targets
appimage:
	@echo "📦 Building AppImage..."
	@chmod +x scripts/build_appimage.sh
	@./scripts/build_appimage.sh

github-release:
ifndef VERSION
	$(error VERSION is not set. Usage: make github-release VERSION=1.0.0)
endif
	@echo "🚀 Creating GitHub release v$(VERSION)..."
	@chmod +x scripts/create_github_release.sh
	@./scripts/create_github_release.sh --version $(VERSION)

# Release management
tag-release:
ifndef VERSION
	$(error VERSION is not set. Usage: make tag-release VERSION=1.0.0)
endif
	@echo "🚀 Creating release tag v$(VERSION)..."
	@echo "1. Updating pubspec.yaml version..."
	@sed -i 's/^version: .*/version: $(VERSION)/' pubspec.yaml
	@echo "2. Committing version update..."
	@git add pubspec.yaml
	@git commit -m "chore: bump version to $(VERSION)" || echo "No changes to commit"
	@echo "3. Creating git tag..."
	@git tag -a v$(VERSION) -m "Release version $(VERSION)"
	@echo "4. Pushing changes and tag..."
	@git push origin $$(git branch --show-current)
	@git push origin v$(VERSION)
	@echo "✅ Release tag v$(VERSION) created and pushed!"

# Complete release workflow
release-all:
ifndef VERSION
	$(error VERSION is not set. Usage: make release-all VERSION=1.0.0)
endif
	@echo "🚀 Starting complete release workflow for v$(VERSION)..."
	@echo ""
	@echo "📋 Step 1/4: Creating git tag and pushing..."
	@make tag-release VERSION=$(VERSION)
	@echo ""
	@echo "📋 Step 2/4: Building AppImage..."
	@make appimage
	@echo ""
	@echo "📋 Step 3/4: Creating GitHub release..."
	@make github-release VERSION=$(VERSION)
	@echo ""
	@echo "📋 Step 4/4: Final verification..."
	@make version-check
	@echo ""
	@echo "✅ Complete release v$(VERSION) finished!"
	@echo "🎉 Your release is now live on GitHub with AppImage attached!"
	@echo ""
	@echo "📁 AppImage location: ./appimage/WinePrefixManager-$(VERSION)-x86_64.AppImage"
	@echo "🔗 Release URL: https://github.com/CrownParkComputing/wine_prefix_manager/releases/tag/v$(VERSION)"

# Check if Flutter is installed
check-flutter:
	@which flutter > /dev/null || (echo "❌ Flutter not found. Please install Flutter first." && exit 1)
	@echo "✅ Flutter is installed: $$(flutter --version | head -n 1)"

# Development setup
setup: check-flutter install
	@echo "🔧 Setting up development environment..."
	@chmod +x scripts/check_version_sync.sh
	@chmod +x scripts/build_appimage.sh
	@chmod +x scripts/create_github_release.sh
	@echo "✅ Development environment ready!"

# Pre-commit checks
pre-commit: format lint test version-check
	@echo "✅ All pre-commit checks passed!" 