# Wine Prefix Manager Scripts

This directory contains utility scripts for building, packaging, and developing Wine Prefix Manager.

## Menu System

For easier access to all build and development functionality, use the interactive menu system:

```bash
# Run the interactive menu
./scripts/menu.sh
```

This provides a user-friendly interface to all build options, including:
- Building packages for specific distributions (Arch, Debian, RPM)
- Building all package types at once
- Creating a full release with version increment and GitHub publishing
- Debug building and running
- Cleaning build directories
- Installing dependencies

## Available Scripts

### menu.sh
An interactive menu system that provides easy access to all build and release functionality.

### build_and_release.sh
The main build and release script that:
- Builds the application for Linux
- Creates distribution packages (tarball, Arch PKGBUILD, Debian .deb, RPM)
- Handles version management
- Can create GitHub releases

```bash
# Examples:
# Build a patch release
./scripts/build_and_release.sh --release-type patch

# Build a specific package type
./scripts/build_and_release.sh --distro arch
./scripts/build_and_release.sh --distro debian
./scripts/build_and_release.sh --distro rpm

# Build all package types if tools are available
./scripts/build_and_release.sh --distro all

# Skip git operations
./scripts/build_and_release.sh --skip-git

# Show help
./scripts/build_and_release.sh --help
```

### debug_build_run.sh
Utility script for development that builds and runs the application in debug mode.

```bash
# Build and run in debug mode
./scripts/debug_build_run.sh

# Only build
./scripts/debug_build_run.sh --build-only

# Only run
./scripts/debug_build_run.sh --run-only

# Clean build
./scripts/debug_build_run.sh --clean
```

### install_dependencies.sh
Installs required dependencies for building and packaging Wine Prefix Manager on various distributions.

```bash
# Auto-detect distribution
./scripts/install_dependencies.sh

# Specify distribution
./scripts/install_dependencies.sh --distro ubuntu
./scripts/install_dependencies.sh --distro debian
./scripts/install_dependencies.sh --distro fedora
./scripts/install_dependencies.sh --distro arch
```

## Package Requirements

To build the various package types, you need specific tools:

- **Debian (.deb) packages**: `dpkg-dev` and `fakeroot`
- **RPM packages**: `rpm-build` and `rpmdevtools`
- **Arch Linux**: `base-devel` package group

You can install these with the `install_dependencies.sh` script.
