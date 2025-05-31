# ISO/CD Management Feature

## Overview
The Wine Prefix Manager now includes a comprehensive ISO/CD management system that allows you to mount ISO files as virtual CD drives in your Wine prefixes, simulating the experience of inserting and ejecting physical CDs.

## Features

### Virtual CD Drive Simulation
- Mount ISO files to appear as a real CD drive (D:) within Wine prefixes
- Automatic Wine registry configuration for CD-ROM drive detection
- Proper mounting using Linux loop devices for authentic CD behavior

### Supported File Formats
- `.iso` - Standard ISO disc images
- `.img` - Raw disc images
- `.bin` - Binary disc images
- `.cue` - Cue sheet files (when paired with .bin)

### User Interface
- **Navigation**: Access through the "ISO/CD" tab in the main navigation rail
- **Prefix Selection**: Choose which Wine prefix to mount the ISO to
- **File Picker**: Browse and select ISO files from your filesystem
- **Real-time Status**: Live updates during mounting/unmounting operations
- **Mounted ISOs List**: View all currently mounted ISOs with details

## How to Use

### Mounting an ISO
1. Navigate to the **ISO/CD** tab in the application
2. Select a Wine prefix from the dropdown menu
3. Click **"Mount ISO"** button
4. Choose your ISO file using the file picker
5. Wait for the mounting process to complete
6. The ISO will appear as drive D: in the selected Wine prefix

### Ejecting an ISO
1. In the "Currently Mounted ISOs" section, find your mounted ISO
2. Click the **eject button** (⏏️) or use the context menu
3. The virtual CD will be safely removed from the prefix

### Viewing ISO Details
- Click the **info button** (ℹ️) or select "Show Details" from the context menu
- View information including:
  - ISO file path
  - Mount point on the system
  - Virtual device path
  - Wine drive letter (D:)
  - Mount timestamp

## Technical Implementation

### System Requirements
- Linux system with `sudo` access (required for loop device operations)
- `losetup` utility (usually part of util-linux package)
- `mount`/`umount` commands

### How It Works
1. **Loop Device Creation**: Creates a virtual block device from the ISO file
2. **Mounting**: Mounts the loop device to a temporary directory
3. **Wine Integration**: Updates Wine registry to recognize the mount as drive D:
4. **Cleanup**: Automatically unmounts and cleans up when ejecting or closing the app

### Security Considerations
- Uses `sudo` for mounting operations (system will prompt for password)
- Temporary mount points are created in `/tmp` with unique names
- Automatic cleanup prevents orphaned mounts

## Integration with Wine Prefixes

### Wine Registry Configuration
The service automatically configures Wine registry entries:
- `HKEY_LOCAL_MACHINE\Software\Wine\Drives` - Drive type registration
- `HKEY_CURRENT_USER\Software\Wine\Drives` - Drive path mapping

### Compatibility
- Works with both Wine and Proton prefixes
- Supports custom Wine builds and system Wine installations
- Automatically detects Wine executable locations

## Error Handling

### Common Issues
- **Permission denied**: Ensure your user can use `sudo`
- **Loop device unavailable**: System may have reached loop device limit
- **Mount failed**: ISO file may be corrupted or unsupported format

### Automatic Cleanup
- Mounted ISOs are automatically unmounted when the application closes
- Failed mounts are cleaned up to prevent resource leaks
- Temporary directories are removed after use

## Usage Tips

1. **Game Installation**: Mount game installation discs and install directly through Wine
2. **CD-ROM Games**: Mount game discs for copy protection that expects physical media
3. **Multiple Prefixes**: Each prefix can have one ISO mounted at a time
4. **Background Mounting**: Mounting operations run in the background with progress updates

## Troubleshooting

If you encounter issues:
1. Check that your user has sudo privileges
2. Ensure the ISO file is not corrupted
3. Verify Wine prefix is properly configured
4. Check system logs for mounting errors
5. Try unmounting and remounting the ISO

The ISO mounting system provides a seamless way to use disc-based software with Wine, eliminating the need for physical CD/DVD drives while maintaining compatibility with copy protection and installation routines that expect physical media. 