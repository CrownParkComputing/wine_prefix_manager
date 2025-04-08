# AppImage Build Script

This directory contains a script to create an AppImage for Wine Prefix Manager.

## Prerequisites

Make sure you have the following dependencies installed:

```bash
# For AppImage creation
sudo apt-get install -y libfuse2 imagemagick

# Ensure Flutter is properly set up
flutter doctor
```

## Building the AppImage

1. Make the build script executable:
   ```bash
   chmod +x scripts/build_appimage.sh
   ```

2. Run the build script:
   ```bash
   ./scripts/build_appimage.sh
   ```

3. The AppImage will be created in the `release` folder:
   ```
   release/Wine_Prefix_Manager-[version]-x86_64.AppImage
   ```

## Running the AppImage

Make the AppImage executable and run it:

```bash
chmod +x release/Wine_Prefix_Manager-*-x86_64.AppImage
./release/Wine_Prefix_Manager-*-x86_64.AppImage
```

## Distributing the AppImage

The AppImage is a standalone executable and can be distributed to users without requiring them to install any dependencies (except perhaps libfuse2 on some systems).

## Customization

- **App Icon**: Replace `assets/icons/app_icon.png` with your application icon (256x256px recommended)
- **Version**: The version is automatically extracted from your `pubspec.yaml` file
- **Metadata**: Edit the AppStream metadata in the script to update app description and details
