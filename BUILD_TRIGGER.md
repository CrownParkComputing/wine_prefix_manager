# Build Trigger

This file is used to trigger GitHub Actions builds.

Last build triggered: October 1, 2025 at 17:55 UTC
Build triggered after fixing GitHub Actions GTK dependencies.

## Recent Changes
- **Fixed GitHub Actions build failure**
- Added comprehensive GTK+3.0 dependencies (libgtk-3-0, libgtk-3-common, etc.)
- Added pkg-config verification for debugging
- **Version bumped to 3.5.0**
- Fixed all lint warnings and errors
- Resolved BuildContext async usage issues
- Updated deprecated Share API to SharePlus
- Fixed private types in public API
- Made constructors const where appropriate
- Built fresh AppImage: WinePrefixManager-20251001.AppImage
- Re-released v3.5.0 tag with build fixes