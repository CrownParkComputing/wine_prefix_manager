# Build and Release Guide

This guide explains how to use the automated build and release system for Wine Prefix Manager.

## Prerequisites

### Required Dependencies
- **Flutter SDK** - For building the Linux application
- **Git** - For version control and pushing changes
- **wget** - For downloading AppImage tools

### Optional Dependencies
- **GitHub CLI (gh)** - For automated GitHub release creation
  ```bash
  # Install on Ubuntu/Debian
  sudo apt install gh
  
  # Install on Arch Linux
  sudo pacman -S github-cli
  
  # Authenticate with GitHub
  gh auth login
  ```
- **ImageMagick** - For generating app icons if none provided
  ```bash
  # Install on Ubuntu/Debian
  sudo apt install imagemagick
  
  # Install on Arch Linux
  sudo pacman -S imagemagick
  ```

## Configuration

1. **Edit the configuration file:**
   ```bash
   nano build_config.conf
   ```

2. **Update the GitHub repository:**
   ```bash
   GITHUB_REPO="yourusername/wine_prefix_manager"
   ```

3. **Add your app icon (optional):**
   - Place a 256x256 PNG icon at `assets/icon.png`
   - Or update `APPIMAGE_ICON_PATH` in the config file

## Usage

The build script supports three types of version bumps:

### Patch Release (Bug fixes)
```bash
./build_and_release.sh patch
```
- Increments the patch version (1.0.0 → 1.0.1)
- Use for bug fixes and small improvements

### Minor Release (New features)
```bash
./build_and_release.sh minor
```
- Increments the minor version (1.0.0 → 1.1.0)
- Use for new features that are backwards compatible

### Major Release (Breaking changes)
```bash
./build_and_release.sh major
```
- Increments the major version (1.0.0 → 2.0.0)
- Use for breaking changes or major rewrites

## What the Script Does

1. **Dependency Check** - Verifies all required tools are installed
2. **Git Status Check** - Warns about uncommitted changes
3. **Version Calculation** - Reads current version and calculates new version
4. **Version Update** - Updates `pubspec.yaml` with new version and build number
5. **Flutter Build** - Cleans and builds the Linux release
6. **AppImage Creation** - Creates a portable AppImage file
7. **Git Operations** - Commits changes and pushes to GitHub
8. **GitHub Release** - Creates a new release with the AppImage as an asset
9. **Launch Option** - Offers to launch the newly created AppImage

## AppImage Details

The script creates a portable AppImage with the following structure:
- **Name**: `WinePrefixManager-{version}-x86_64.AppImage`
- **Desktop Integration**: Includes `.desktop` file for proper integration
- **Icon**: Uses your provided icon or creates a placeholder
- **Permissions**: Automatically made executable

## GitHub Release

If GitHub CLI is configured, the script will:
- Create a new release with the version tag
- Generate release notes with installation instructions
- Upload the AppImage as a release asset
- Set appropriate release metadata

## Troubleshooting

### Common Issues

1. **Flutter build fails**
   ```bash
   flutter doctor
   flutter clean && flutter pub get
   ```

2. **Git authentication issues**
   ```bash
   gh auth login
   # or set up SSH keys
   ```

3. **AppImage creation fails**
   - Check if you have write permissions in the project directory
   - Ensure FUSE is installed on your system

4. **Permission denied on script execution**
   ```bash
   chmod +x build_and_release.sh
   ```

### Manual Steps (if automation fails)

If the automated process fails, you can perform steps manually:

1. **Manual version update:**
   ```bash
   # Edit pubspec.yaml version line
   nano pubspec.yaml
   ```

2. **Manual Flutter build:**
   ```bash
   flutter clean
   flutter pub get
   flutter build linux --release
   ```

3. **Manual AppImage creation:**
   ```bash
   # Follow the AppImage creation steps in the script
   mkdir -p appimage/AppDir
   # ... (see script for detailed steps)
   ```

4. **Manual GitHub release:**
   ```bash
   git add .
   git commit -m "Release v{version}"
   git push origin main
   gh release create v{version} --title "Wine Prefix Manager v{version}" --notes "Release notes..."
   gh release upload v{version} WinePrefixManager-{version}-x86_64.AppImage
   ```

## File Structure

After running the script, your project will have:
```
wine_prefix_manager/
├── build_and_release.sh          # Main build script
├── build_config.conf             # Configuration file
├── WinePrefixManager-{version}-x86_64.AppImage  # Generated AppImage
├── appimage/                     # AppImage build directory
├── build/                        # Flutter build output
└── pubspec.yaml                  # Updated with new version
```

## Customization

You can customize the build process by:

1. **Modifying `build_config.conf`** - Change app names, paths, and settings
2. **Editing the script** - Add custom build steps or modify existing ones
3. **Creating release notes templates** - Define custom release note formats
4. **Adding pre/post build hooks** - Insert custom commands before or after main steps

## Tips

- Always test your app before running a release build
- Use patch releases for quick fixes
- Use minor releases for new features
- Use major releases sparingly for significant changes
- Keep your GitHub repository clean and organized
- Regularly update your app icon and metadata

## Support

If you encounter issues with the build process:
1. Check the console output for specific error messages
2. Verify all dependencies are properly installed
3. Ensure your Git repository is properly configured
4. Check GitHub authentication if release creation fails 