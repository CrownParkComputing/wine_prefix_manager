# Wine Prefix Manager

A modern Flutter application for managing Wine/Proton prefixes on Linux with comprehensive gaming features, ISO mounting, and built-in IGDB integration.

![Version](https://img.shields.io/badge/version-3.3.1-blue)
![Platform](https://img.shields.io/badge/platform-Linux-green)
![License](https://img.shields.io/badge/license-MIT-red)

## ✨ Features

### 🎮 Game Library Management
- **Visual Game Library** - Beautiful grid view with cover art and metadata
- **IGDB Integration** - Automatic game metadata, cover art, and screenshots
- **Game Categories** - Organize your games with custom categories
- **Advanced Search** - Find games quickly with powerful search functionality
- **Game Details** - Comprehensive game information and launch options

### 🍷 Wine Prefix Management

- **Safe Ejection** - Clean unmounting with automatic cleanup

### 💾 Backup & Restore
- **Complete Backup System** - Backup entire prefixes with games and settings
- **Selective Restore** - Restore specific components or complete prefixes
- **Compressed Archives** - Efficient storage with compression
- **Backup Scheduling** - Automatic backup reminders and management

### 📁 File Management
- **Integrated File Browser** - Browse and manage prefix files directly
- **Quick Access** - Jump to common directories (Program Files, System32, etc.)
- **File Operations** - Copy, move, delete files within prefixes
- **Registry Editing** - Access to Wine registry for advanced configuration

### ⚙️ Advanced Configuration
- **Environment Variables** - Manage prefix-specific environment variables
- **Controller Support** - Built-in controller fixes for gaming
- **Wine Version Management** - Switch between different Wine versions
- **Performance Optimization** - DXVK, VKD3D integration for 64-bit prefixes

### 🔧 System Integration
- **One-Click AppImage** - Portable, no-installation-required distribution
- **Desktop Integration** - .desktop file for system menu integration
- **Logging System** - Comprehensive logging for troubleshooting
- **Power Management** - Prevent system sleep during long operations

## 🚀 Quick Start

### Download & Install

1. **Download the AppImage** from [Releases](https://github.com/CrownParkComputing/wine_prefix_manager/releases/latest)
2. **Make it executable:**
   ```bash
   chmod +x WinePrefixManager-*.AppImage
   ```
3. **Run the application:**
   ```bash
   ./WinePrefixManager-*.AppImage
   ```

### First Launch Setup

1. **Configure Prefix Directory** - Choose where to store your Wine prefixes
2. **Set Game Library Path** - Select your games directory for automatic detection
3. **Install ISO Mounting** (Optional) - Run setup for password-free ISO mounting:
   ```bash
   ./scripts/setup_iso_mounting.sh
   ```

## 🎮 Using the Application

### Creating Wine Prefixes
1. Navigate to **Manage Prefixes** tab
2. Click **Create New Prefix**
3. Choose Wine/Proton version and architecture
4. Configure initial settings and dependencies
5. Wait for automatic setup completion

### Managing Your Game Library
1. Go to **Game Library** tab
2. Add games manually or let the app auto-detect
3. Fetch metadata from IGDB for cover art and details
4. Organize games into categories
5. Launch games directly from the library

### Mounting ISO Files
1. Open **ISO/CD** tab
2. Select target Wine prefix
3. Click **Mount ISO** and choose your file
4. The ISO appears as drive D: in the selected prefix
5. Eject safely when done

### Backup & Restore
1. Access **Files & Backup** tab
2. Select prefixes to backup
3. Choose backup location and options
4. Monitor backup progress
5. Restore from backups when needed

## 🔧 Development

### Prerequisites
- Flutter SDK (latest stable) with Linux desktop support
- Wine or Proton installed
- Git

### Building from Source

1. **Clone and setup:**
   ```bash
   git clone https://github.com/CrownParkComputing/wine_prefix_manager.git
   cd wine_prefix_manager
   make setup
   ```

2. **Development build:**
   ```bash
   make build
   flutter run -d linux
   ```

### Available Commands
```bash
# Development
make setup          # Setup development environment
make build          # Build the application
make test           # Run tests
make lint           # Run linter
make format         # Format code
make clean          # Clean build artifacts

# Distribution
make appimage       # Build AppImage
make release-all VERSION=x.y.z  # Complete release workflow

# Version Management
make version-check  # Check version synchronization
make version-fix    # Auto-fix version issues
```

### IGDB Integration Setup (Developers)

For developers building from source:

1. **Get IGDB credentials** from [Twitch Developer Console](https://dev.twitch.tv/console/apps)
2. **Copy environment template:**
   ```bash
   cp env.example .env
   ```
3. **Add credentials to .env:**
   ```env
   IGDB_CLIENT_ID=your_client_id_here
   IGDB_CLIENT_SECRET=your_client_secret_here
   ```

## 📁 Project Structure

```
wine_prefix_manager/
├── lib/                    # Flutter source code
│   ├── pages/             # Application pages/screens
│   ├── services/          # Core business logic services
│   ├── widgets/           # Reusable UI components
│   ├── models/            # Data models
│   ├── providers/         # State management
│   └── theme/             # UI theming
├── scripts/               # Build and utility scripts
│   ├── build_appimage.sh  # AppImage creation
│   ├── create_github_release.sh  # GitHub release automation
│   ├── check_version_sync.sh     # Version management
│   └── setup_iso_mounting.sh     # ISO mounting setup
├── appimage/              # AppImage build artifacts
├── website/               # Project website
├── Makefile              # Build orchestration
├── pubspec.yaml          # Flutter dependencies
└── env.example           # Environment template
```

## 🐛 Troubleshooting

### Common Issues

1. **AppImage won't run:**
   ```bash
   # Install FUSE if needed
   sudo apt install fuse          # Ubuntu/Debian
   sudo pacman -S fuse           # Arch Linux
   sudo dnf install fuse         # Fedora
   ```

2. **ISO mounting requires password:**
   ```bash
   # Run the setup script once
   sudo ./scripts/setup_iso_mounting.sh
   ```

3. **Games won't launch:**
   - Check prefix configuration in Manage Prefixes
   - Verify Wine/Proton version compatibility
   - Check logs tab for detailed error messages

4. **IGDB integration not working:**
   - For users: Should work automatically
   - For developers: Check IGDB credentials in .env file

### Debug Information

- **Logs**: Available in the "Logs" tab within the application
- **Verbose logging**: Run with `flutter run -d linux --verbose`
- **Log files**: Check application data directory for persistent logs

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make your changes
4. Run quality checks: `make pre-commit`
5. Commit changes: `git commit -m "Add new feature"`
6. Push to branch: `git push origin feature/new-feature`
7. Submit a pull request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Support

- **Issues**: [GitHub Issues](https://github.com/CrownParkComputing/wine_prefix_manager/issues)
- **Discussions**: [GitHub Discussions](https://github.com/CrownParkComputing/wine_prefix_manager/discussions)
- **Releases**: [GitHub Releases](https://github.com/CrownParkComputing/wine_prefix_manager/releases)

---

**Made with ❤️ for the Linux gaming community** 