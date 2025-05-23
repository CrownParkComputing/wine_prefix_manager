# GitHub Actions for Wine Prefix Manager

This repository includes GitHub Actions workflows for building and releasing the Wine Prefix Manager application.

## Available Workflows

### CI Build
The CI workflow runs on every push to the main branch and on pull requests. It performs:
- Code analysis
- Debug build for Linux

### Build and Release
The release workflow builds and packages Wine Prefix Manager for Linux in multiple formats:
- Tar.gz archive
- Debian (.deb) package
- RPM (.rpm) package
- AppImage

## Triggering Builds

### Manual Builds
You can manually trigger a build from the GitHub Actions tab:
1. Navigate to the "Actions" tab in your repository
2. Select "Build and Release" workflow
3. Click "Run workflow"
4. Enter the version number (e.g., 1.9.1)
5. Click "Run workflow"

### Automated Releases
To create an official release:
1. Create and push a git tag with a version number:
   ```bash
   git tag -a v1.9.2 -m "Release v1.9.2"
   git push origin v1.9.2
   ```

2. The Build and Release workflow will automatically run, creating all package formats.
3. A GitHub Release will be created with all the build artifacts.

## Package Requirements

- The .deb package requires Wine to be installed
- The .rpm package requires Wine to be installed
- The AppImage bundles most dependencies, but still requires Wine to be installed
