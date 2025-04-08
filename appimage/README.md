# Creating an AppImage for Wine Prefix Manager

This directory contains tools and instructions for creating a distributable AppImage of Wine Prefix Manager.

## Prerequisites

- AppImage tools: `sudo apt-get install -y libfuse2`
- Standard build tools: `sudo apt-get install -y build-essential`

## Building the AppImage

1. Make sure you have all dependencies installed:
   ```bash
   flutter pub get
   ```

2. Make the build script executable:
   ```bash
   chmod +x appimage/build-appimage.sh
   ```

3. Run the build script:
   ```bash
   ./appimage/build-appimage.sh
   ```

4. The AppImage will be created in the project root directory:
   ```
   Wine_Prefix_Manager-<version>-x86_64.AppImage
   ```

## Customizing the AppImage

- **Icon**: Replace `assets/icon/icon.png` with your application icon (256x256px PNG recommended)
- **Desktop Entry**: Edit `appimage/build-appimage.sh` to modify the .desktop file contents

## Testing the AppImage

After building, make the AppImage executable and run it:

```bash
chmod +x Wine_Prefix_Manager-*-x86_64.AppImage
./Wine_Prefix_Manager-*-x86_64.AppImage
```

## Distribution

The AppImage can be distributed as a single file. Users on most Linux distributions can run it after making it executable, without installing any dependencies (except perhaps libfuse2 on some systems).
