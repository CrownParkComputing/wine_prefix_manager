# Release Process for Wine Prefix Manager

This document outlines the automated release process for Wine Prefix Manager, including version management, AppImage creation, and GitHub release automation.

## 🚀 Quick Release

For a complete release with all automation:

```bash
# Create and push version 3.1.0 with AppImage and GitHub release
make release-all VERSION=3.1.0
```

This single command will:
1. ✅ Update `pubspec.yaml` version
2. ✅ Commit and push version change
3. ✅ Create and push git tag
4. ✅ Build Flutter app for Linux
5. ✅ Create AppImage package
6. ✅ Create GitHub release
7. ✅ Upload AppImage to GitHub
8. ✅ Verify version synchronization

## 📋 Step-by-Step Release Process

### 1. Version Management

#### Check Current Status
```bash
make version-info
```

#### Verify Version Sync
```bash
make version-check
```

#### Create Release Tag
```bash
make tag-release VERSION=3.1.0
```

### 2. Build Distribution

#### Build AppImage
```bash
make appimage
```

This creates:
- `./appimage/WinePrefixManager-3.1.0-x86_64.AppImage` (portable Linux executable)
- Complete AppDir structure for debugging

### 3. GitHub Release

#### Automated GitHub Release
```bash
# Requires GITHUB_TOKEN environment variable
export GITHUB_TOKEN="your_github_token_here"
make github-release VERSION=3.1.0
```

#### Manual GitHub Release
```bash
./scripts/create_github_release.sh --version 3.1.0 --token YOUR_TOKEN
```

## 🔧 Manual Process

If you prefer manual control over each step:

```bash
# 1. Update version in pubspec.yaml manually
vim pubspec.yaml

# 2. Commit changes
git add pubspec.yaml
git commit -m "chore: bump version to 3.1.0"

# 3. Create and push tag
git tag -a v3.1.0 -m "Release version 3.1.0"
git push origin main
git push origin v3.1.0

# 4. Build AppImage
make appimage

# 5. Create GitHub release (manual via web interface or CLI)
./scripts/create_github_release.sh --version 3.1.0
```

## 🛠️ Scripts Overview

### Version Sync Script (`scripts/check_version_sync.sh`)
- **Purpose**: Ensures `pubspec.yaml` version matches latest git tag
- **Usage**: `./scripts/check_version_sync.sh [--fix] [--help]`
- **Features**:
  - Colorized output
  - Version normalization (handles build numbers)
  - Auto-fix mode with `--fix`
  - Proper exit codes for CI/CD

### AppImage Builder (`scripts/build_appimage.sh`)
- **Purpose**: Creates portable Linux AppImage from Flutter build
- **Usage**: `./scripts/build_appimage.sh`
- **Output**: `./appimage/WinePrefixManager-{VERSION}-x86_64.AppImage`
- **Features**:
  - Automatic dependency bundling
  - Desktop integration files
  - Icon handling (uses assets/icon.png if available)
  - Proper AppRun script for environment setup

### GitHub Release Creator (`scripts/create_github_release.sh`)
- **Purpose**: Automates GitHub release creation with AppImage upload
- **Usage**: `./scripts/create_github_release.sh --version 3.1.0`
- **Features**:
  - Automated release notes generation
  - AppImage upload to GitHub releases
  - Changelog generation from git commits
  - Draft and prerelease support

## 📦 Distribution Formats

### AppImage
- **File**: `WinePrefixManager-{VERSION}-x86_64.AppImage`
- **Size**: ~11MB
- **Compatibility**: Most Linux distributions
- **Installation**: None required (portable)
- **Usage**: 
  ```bash
  chmod +x WinePrefixManager-3.1.0-x86_64.AppImage
  ./WinePrefixManager-3.1.0-x86_64.AppImage
  ```

## 🔐 Prerequisites

### Development Environment
- Flutter SDK (latest stable)
- Git
- Linux x86_64 system
- Standard Linux utilities (wget, curl, jq)

### For GitHub Releases
- GitHub Personal Access Token with repo permissions
- `jq` command-line JSON processor
- `curl` for API requests

#### Creating GitHub Token
1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. Generate new token (classic)
3. Select scopes: `repo` (Full control of private repositories)
4. Copy token and set environment variable:
   ```bash
   export GITHUB_TOKEN="ghp_your_token_here"
   ```

## ⚙️ Makefile Targets

### Version Management
- `make version-check` - Check version synchronization
- `make version-fix` - Auto-create git tag for current version
- `make version-info` - Show current version information

### Development
- `make build` - Build Flutter app for Linux
- `make clean` - Clean build artifacts
- `make test` - Run tests
- `make format` - Format Dart code
- `make lint` - Run linter
- `make install` - Get Flutter dependencies

### Distribution
- `make appimage` - Build AppImage
- `make github-release VERSION=x.y.z` - Create GitHub release
- `make release-all VERSION=x.y.z` - Complete release workflow

### Setup
- `make setup` - Set up development environment
- `make pre-commit` - Run all pre-commit checks

## 🔄 CI/CD Integration

### GitHub Actions
The repository includes automated workflows:

- **Version Check**: Runs on push/PR to verify version sync
- **Auto Comments**: Comments on PRs when versions are out of sync
- **Release Workflow**: Can be extended for automated releases

### Manual Trigger
Workflows can be triggered manually via GitHub's workflow dispatch feature.

## 📝 Release Notes

Release notes are automatically generated and include:
- **What's New**: Major features and improvements
- **Technical Improvements**: UX and technical changes
- **Bug Fixes**: Issues resolved
- **Download Instructions**: How to install and run
- **Changelog**: Git commit history since last release
- **System Requirements**: Dependencies and compatibility

## 🐛 Troubleshooting

### Version Sync Issues
```bash
# Check what's wrong
make version-check

# Auto-fix if pubspec.yaml is ahead
make version-fix
```

### AppImage Build Fails
```bash
# Clean and rebuild
make clean
make appimage
```

### GitHub Release Fails
```bash
# Check token permissions
echo $GITHUB_TOKEN

# Verify tag exists
git tag | grep v3.1.0

# Verify AppImage exists
ls -la appimage/WinePrefixManager-*-x86_64.AppImage
```

## 📊 Release Checklist

Before creating a release:

- [ ] All tests pass (`make test`)
- [ ] Code is formatted (`make format`)
- [ ] No linter errors (`make lint`)
- [ ] Version is updated in pubspec.yaml
- [ ] Changes are documented
- [ ] Git tag is created and pushed
- [ ] AppImage builds successfully
- [ ] AppImage is tested locally
- [ ] GitHub token is configured
- [ ] Release notes are reviewed

## 🎯 Best Practices

1. **Use Semantic Versioning**: MAJOR.MINOR.PATCH
2. **Test AppImage**: Always test locally before release
3. **Version Sync**: Keep pubspec.yaml and git tags synchronized
4. **Clear Commit Messages**: Use conventional commit format
5. **Document Changes**: Update README and changelog for major changes
6. **Security**: Never commit GitHub tokens or sensitive data

## 📱 Post-Release

After a successful release:

1. **Test the GitHub release**: Download and test the AppImage
2. **Update documentation**: If needed for new features
3. **Announce**: Share the release with users
4. **Monitor**: Watch for user feedback and issues
5. **Plan next release**: Based on feedback and roadmap 